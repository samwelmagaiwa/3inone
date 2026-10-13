<?php

namespace App\Services\Rental;

use App\Models\User;
use App\Models\Rental\Property;
use App\Models\Rental\House;
use App\Models\Rental\TenantProfile;
use App\Models\Rental\RentalAgreement;
use App\Models\Rental\RentBill;
use App\Models\Rental\RentalPayment;
use App\Models\Rental\RentalReceipt;
use App\Rules\UniquePhoneInBusiness;
use App\Services\SmsService;
use App\Support\Tenancy\BusinessOwner;
use App\Support\Tenancy\TenantContext;
use App\Support\TemporaryPassword;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Carbon\Carbon;

class RentalService
{
    /**
     * Onboard a new tenant and assign them to a house.
     */
    public function onboardTenant(array $data)
    {
        return DB::transaction(function () use ($data) {
            // 1. Create User account if not exists. The email is the tenant's sign-in name and
            // names the same person whichever landlord onboards them. A phone number does not:
            // another business's driver or tenant may use the same number, so by phone we only
            // recognise someone inside THIS landlord's own business.
            $user = User::where('email', $data['email'])->first();

            if (!$user && !empty($data['phone_number'])) {
                $business = BusinessOwner::ofUser($data['created_by'] ?? null) ?? TenantContext::writeOwner();
                $user = (new UniquePhoneInBusiness($business))->findUser((string) $data['phone_number']);
            }

            $temporaryPassword = null;

            if (!$user) {
                // No shared default: a password the landlord was not given is a password
                // anyone can try on every tenant. A one-time one is generated, handed back
                // once so the landlord can pass it on, and must be replaced at first sign-in.
                $password = $data['password'] ?? null;
                if ($password === null || $password === '') {
                    $password = $temporaryPassword = TemporaryPassword::generate();
                }

                $user = new User([
                    'name' => $data['name'],
                    'email' => $data['email'],
                    'phone_number' => $data['phone_number'],
                    'password' => bcrypt($password),
                    'role' => 'tenant',
                    'service_type' => 'rental',
                    // Whoever onboarded them: this ties the tenant to that account.
                    'created_by' => $data['created_by'] ?? null,
                    'is_active' => true,
                ]);
                $user->must_change_password = true;
                $user->save();
            } elseif (strtolower((string) $user->role) !== 'tenant') {
                // An existing account is reused only when it already is a tenant.
                // Rewriting the role of whoever the email or phone happens to match
                // would silently demote a landlord, admin or staff member.
                throw new \InvalidArgumentException(
                    'This email or phone number already belongs to an account that is not a tenant.'
                );
            }

            // 2. Create Tenant Profile
            // A tenant is one person even when several landlords deal with them, so look
            // for an existing profile across businesses and only fill it in the first
            // time: one landlord's onboarding must never rewrite what another recorded.
            TenantProfile::withoutAccountScope()->firstOrCreate(
                ['user_id' => $user->id],
                [
                    'gender' => $data['gender'] ?? null,
                    'dob' => $data['dob'] ?? null,
                    'id_number' => $data['nida'] ?? ($data['id_details']['number'] ?? ($data['id_number'] ?? null)),
                    'id_state' => $data['id_details']['state'] ?? null,
                    'id_expiration' => $data['id_details']['expiration'] ?? null,
                    'occupation' => $data['employment']['title'] ?? ($data['occupation'] ?? null),
                    'employment' => $data['employment'] ?? null,
                    'emergency_contact_name' => $data['emergency_contact']['name'] ?? ($data['emergency_contact_name'] ?? null),
                    'emergency_contact_phone' => $data['emergency_contact']['phone'] ?? ($data['emergency_contact_phone'] ?? null),
                    'history' => $data['history'] ?? null,
                    'occupants' => $data['occupants'] ?? null,
                    'pets' => $data['pets'] ?? null,
                    'photo_url' => $data['photo_url'] ?? null,
                    'notes' => $data['notes'] ?? null,
                ]
            );

            // 3. Create Rental Agreement
            $agreement = RentalAgreement::create([
                'tenant_id' => $user->id,
                'house_id' => $data['house_id'],
                'selected_units' => $data['selected_units'] ?? null,
                'start_date' => $data['start_date'] ?? now(),
                'rent_cycle' => $data['rent_cycle'] ?? 'monthly',
                'rent_amount' => $data['rent_amount'],
                'deposit_paid' => $data['deposit_paid'] ?? 0,
                'status' => 'active',
            ]);

            // 4. Update House status
            $house = House::find($data['house_id']);
            $house->update([
                'status' => 'occupied',
                'current_tenant_id' => $user->id,
            ]);

            // 5. Generate first bill
            $this->generateBillForAgreement($agreement, Carbon::parse($agreement->start_date));

            return [
                'user' => $user,
                'agreement' => $agreement,
                // Only set when this call created the account; null for a tenant who
                // already had one (they keep the password they chose).
                'temporary_password' => $temporaryPassword,
            ];
        });
    }

    /**
     * Generate a rent bill for a specific agreement and period.
     */
    public function generateBillForAgreement(RentalAgreement $agreement, Carbon $date)
    {
        $monthYear = $date->format('m-Y');

        // Avoid duplicate bills for same period
        $existing = RentBill::where('agreement_id', $agreement->id)
            ->where('month_year', $monthYear)
            ->first();
        if ($existing)
            return $existing;

        // Calculate total amount (Rent + Utilities if applicable)
        $totalAmount = $agreement->rent_amount;

        if ($agreement->utility_charges) {
            foreach ($agreement->utility_charges as $utility) {
                if (isset($utility['amount']) && isset($utility['billing_type']) && $utility['billing_type'] === 'fixed') {
                    $totalAmount += $utility['amount'];
                }
            }
        }

        $dueDay = $agreement->due_day ?? 5;
        $dueDate = $date->copy()->startOfMonth()->addDays($dueDay - 1);

        return RentBill::create([
            'agreement_id' => $agreement->id,
            'month_year' => $monthYear,
            'amount_due' => $totalAmount,
            'balance' => $totalAmount,
            'due_date' => $dueDate,
            'status' => 'unpaid',
        ]);
    }

    /**
     * Record a payment against a bill.
     */
    public function recordPayment(array $data)
    {
        $payment = DB::transaction(function () use ($data) {
            $bill = RentBill::findOrFail($data['bill_id']);
            $amountPaid = $data['amount_paid'];

            // Validate: prevent overpayment
            if ($amountPaid > $bill->balance) {
                throw new \Exception('Cannot pay more than the balance. Maximum allowed: ' . $bill->balance);
            }

            // 1. Create Payment record
            $payment = RentalPayment::create([
                'bill_id' => $bill->id,
                'tenant_id' => $bill->agreement->tenant_id,
                'amount_paid' => $amountPaid,
                'payment_date' => $data['payment_date'] ?? now(),
                'payment_method' => $data['payment_method'],
                'transaction_reference' => $data['transaction_reference'] ?? null,
                'collector_id' => $data['collector_id'],
                'notes' => $data['notes'] ?? null,
            ]);

            // 2. Update Bill balance and status
            $newBalance = $bill->balance - $amountPaid;
            $status = 'partial';
            if ($newBalance <= 0) {
                $status = 'paid';
                $newBalance = 0;
            }

            $bill->update([
                'balance' => $newBalance,
                'status' => $status,
            ]);

            // 3. Generate Receipt
            $this->generateReceipt($payment);

            return $payment;
        });

        // The tenant is told once, and only after the payment is safely recorded: a text
        // sent inside the transaction would go out even if it were rolled back, and a
        // failing SMS must never undo a payment that was taken.
        $this->sendReceiptSms($payment);

        return $payment;
    }

    /** The business a rental receipt or text is from: the landlord's (see Business::identityForProperty). */
    private function businessOfProperty(?Property $property): array
    {
        return \App\Models\Business::identityForProperty($property);
    }

    private function sendReceiptSms(RentalPayment $payment): void
    {
        try {
            $payment->loadMissing('tenant', 'receipt', 'bill');

            $payment->loadMissing('bill.agreement.house.property');

            SmsService::sendPaymentReceipt(
                $payment->tenant->phone_number,
                $payment->amount_paid,
                $payment->receipt->receipt_number,
                $payment->bill->balance,
                $this->businessOfProperty($payment->bill->agreement->house->property),
            );
        } catch (\Throwable $e) {
            Log::warning('Payment receipt SMS could not be sent.', ['payment_id' => $payment->id, 'error' => $e->getMessage()]);
        }
    }

    /**
     * Generate a digital receipt for a payment.
     */
    public function generateReceipt(RentalPayment $payment)
    {
        $payment->load('bill.agreement.house.property', 'tenant', 'collector');

        $receiptNumber = 'RCP-' . strtoupper(Str::random(8));

        // Whose receipt it is: the landlord's business, so the tenant can see who they paid.
        $business = $this->businessOfProperty($payment->bill->agreement->house->property);

        $details = [
            'receipt_number' => $receiptNumber,
            'date' => Carbon::parse($payment->payment_date)->format('Y-m-d'),
            'business_name' => $business['name'],
            'business_address' => $business['address'],
            'business_phone' => $business['phone'],
            'business_tin' => $business['tin'],
            'business_email' => $business['email'],
            'business_logo_url' => $business['logo_url'],
            'tenant_name' => $payment->tenant->name,
            'house_number' => $payment->bill->agreement->house->house_number,
            'property_name' => $payment->bill->agreement->house->property->name,
            'period' => $payment->bill->month_year,
            'amount_paid' => $payment->amount_paid,
            'balance_remaining' => $payment->bill->balance,
            'payment_method' => $payment->payment_method,
            'collector_name' => $payment->collector->name,
        ];

        return RentalReceipt::create([
            'payment_id' => $payment->id,
            'receipt_number' => $receiptNumber,
            'details' => $details,
        ]);
    }

    /**
     * Generate bills for all active agreements for the current/next month.
     */
    public function generateMonthlyBills()
    {
        $agreements = RentalAgreement::where('status', 'active')->get();
        $count = 0;
        $date = now()->addDays(7); // Look ahead 7 days to generate next month's bill early

        foreach ($agreements as $agreement) {
            /** @var \App\Models\Rental\RentalAgreement $agreement */
            $bill = $this->generateBillForAgreement($agreement, $date);
            if ($bill->wasRecentlyCreated)
                $count++;
        }

        return $count;
    }

    /**
     * Check for unpaid bills past due date and mark them as overdue.
     */
    public function processOverdueBills()
    {
        $bills = RentBill::where('status', '!=', 'paid')
            ->where('status', '!=', 'overdue')
            ->where('due_date', '<', now())
            ->with('agreement.tenant', 'agreement.house')
            ->get();

        foreach ($bills as $bill) {
            /** @var \App\Models\Rental\RentBill $bill */
            $bill->update(['status' => 'overdue']);

            // Trigger SMS notification, from the landlord's business
            SmsService::sendOverdueAlert(
                $bill->agreement->tenant->phone_number,
                $bill->agreement->house->house_number,
                $bill->balance,
                $this->businessOfProperty($bill->agreement->house->property),
            );
        }

        return $bills->count();
    }
}

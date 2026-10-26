<?php

namespace App\Support\Ai;

use App\Models\User;

/**
 * What the assistant knows about USING the app, so a new user can simply ask "how do I...". The guide is cut to the person: only the
 * services their business has and the sections their rights open (the same rule as the menu), so it never explains a screen they cannot
 * see. It rides inside the system prompt, so a how-to question needs no data lookup and is answered in one fast AI call.
 *
 * Keep the menu names here the same as the app's menus. Each entry: service, who (inventory rights `any`, or `roles`/`grants`), text.
 */
final class AppGuide
{
    /** @return array<int, array<string, mixed>> */
    private static function entries(): array
    {
        $shop = fn (array $any, string $text, string $sid = 'inventory') => ['service' => $sid, 'any' => $any, 'text' => $text];

        return [
            // ---- Shop / depot
            $shop(['inv_view_products'], 'PRODUCTS: menu "Products" lists your goods with stock and price. To add one: Products > Add, fill the name, buying price, selling price and starting quantity, then save. The product shows low-stock warnings when it falls to its minimum.'),
            $shop(['inv_create_sales'], 'SELLING: menu "Sales" is the till. Tap the goods to add them to the cart, optionally pick the customer (needed for credit), choose how it is paid (paid in full, part payment, or on credit) and confirm. A receipt is shown after. Mistakes: a sale can be cancelled or returned from the sales history by someone allowed.'),
            $shop(['inv_manage_stock'], 'STOCK: menu "Stock levels" shows what is in store; use it to add stock received, count stock, or report damaged goods (write-off).'),
            $shop(['inv_report_damage', 'inv_manage_stock'], 'DAMAGED GOODS: report them from the stock section (write-off) so the stock and profit stay true.'),
            $shop(['inv_view_credit'], 'CUSTOMERS AND CREDIT: menu "Customers & Credit" lists customers and what each owes; menu "Debts" has two tabs, money owed to you and money you owe. To record a debt from before the app: Debts > Add > write the name, amount and date. Customers pay it off in parts with "Record payment".'),
            $shop(['inv_view_reports'], 'MONTHLY REPORT: menu "Monthly report" shows the month\'s sales, profit and spending against last month, your profit target (set it there), where the business stands, and a "Where to improve" advice card. Menu "Reports" has the detailed reports.'),
            $shop(['inv_view_expenses'], 'EXPENSES: record spending (rent, transport, electricity...) under reports/expenses; mark personal spending as personal so it does not reduce business profit.'),
            $shop(['inv_view_purchasing'], 'PURCHASING: menu "Purchasing" is for suppliers, purchase orders and receiving goods; what you owe suppliers shows under Debts.'),
            $shop(['inv_manage_settings'], 'SETTINGS: menu "Settings" holds business settings; Settings > Language changes the app language; Settings > User management creates staff and sets what each person may open.'),
            // ---- Salon
            ['service' => 'salon', 'any' => ['inv_create_sales'], 'text' => 'SALON TILL: menu "Sales" records services and goods; every service line needs the stylist who did it. "Appointments" books clients; "Walk-ins" is the queue of people waiting; "Come back" lists clients due for a return visit and can text them.'],
            ['service' => 'salon', 'any' => ['inv_view_reports', 'inv_create_sales'], 'text' => 'SALON PEOPLE: "Stylists" shows how each stylist did; "Team" holds staff, attendance and payroll; "Feedback" shows client complaints and ratings; "Insights" shows trends.'],
            ['service' => 'salon', 'any' => ['inv_manage_settings'], 'text' => 'SALON SETUP: "Salon settings", "Business profile", "Offers & texts" (vouchers, loyalty, messages), "Branches", "Equipment" and "Goods by branch" are in the menu for the owner.'],
            // ---- Transport
            ['service' => 'transport', 'roles' => ['admin'], 'grants' => ['manage_drivers_transport'], 'text' => 'DRIVERS: Dashboard > Drivers > Add Driver, fill the details and save. A driver gets a login to see their own payments and debt.'],
            ['service' => 'transport', 'roles' => ['admin'], 'grants' => ['manage_vehicles_transport'], 'text' => 'VEHICLES: menu "Vehicles" lists them; add one with its plate number, then assign it to a driver.'],
            ['service' => 'transport', 'roles' => ['admin'], 'grants' => ['manage_payments_transport'], 'text' => 'PAYMENTS: menu "Payments", choose the driver, enter the amount and channel. It lowers the driver\'s debt. "Receipts" generates a receipt for a payment and can send it by email or WhatsApp.'],
            ['service' => 'transport', 'roles' => ['admin'], 'grants' => ['manage_debts_transport', 'view_reports_transport'], 'text' => 'DEBTS AND REPORTS: "Debt records" shows which drivers owe and for how long; "Analytics" and "Reports" give totals and trends; "Reminders" and "Communications" message drivers.'],
            ['service' => 'transport', 'roles' => ['driver'], 'text' => 'AS A DRIVER you see only your own dashboard, payment history, receipts and reminders.'],
            // ---- Rental
            ['service' => 'rental', 'roles' => ['admin', 'landlord'], 'grants' => ['manage_properties_rental', 'manage_houses_rental'], 'text' => 'PROPERTIES AND HOUSES: menu "Properties" > create a property, add blocks, then add houses with their rent. A house shows vacant, occupied or under maintenance.'],
            ['service' => 'rental', 'roles' => ['admin', 'landlord'], 'grants' => ['onboard_tenants_rental', 'manage_agreements_rental'], 'text' => 'TENANTS AND LEASES: menu "Tenants" > onboard a tenant, then "Lease agreements" > create the agreement for a house (rent, deposit, start date). Rent bills are then made each cycle.'],
            ['service' => 'rental', 'roles' => ['admin', 'landlord'], 'grants' => ['manage_billing_rental', 'view_reports_rental'], 'text' => 'RENT: menu "Rent payments" to record what a tenant paid; "Arrears" lists who owes; "Reports" gives totals.'],
            ['service' => 'rental', 'roles' => ['admin', 'landlord', 'caretaker', 'tenant', 'vendor'], 'grants' => ['manage_maintenance_rental'], 'text' => 'MAINTENANCE: menu "Maintenance" lists repair requests; tenants and caretakers raise them, owners assign them to a vendor, vendors mark them done.'],
            ['service' => 'rental', 'roles' => ['tenant'], 'text' => 'AS A TENANT: menu "My Account" shows your lease, rent bills and payments; raise a repair from "Maintenance".'],
        ];
    }

    private static function applies(array $e, User $user): bool
    {
        if (!$user->canUseService($e['service'])
            && !($e['service'] === 'inventory' && $user->canUseService('salon'))) {
            return false;
        }
        if (isset($e['any'])) {
            foreach ($e['any'] as $right) {
                if ($user->hasInventoryPermission($right)) {
                    return true;
                }
            }

            return false;
        }
        if (in_array(strtolower((string) $user->role), $e['roles'], true)) {
            return true;
        }
        foreach ($e['grants'] ?? [] as $g) {
            if ($user->hasExplicitGrant($g)) {
                return true;
            }
        }

        return false;
    }

    /** The guide text for this person: general help plus the sections their services and rights open. */
    public static function forUser(User $user): string
    {
        $general = 'GENERAL: sign in with your phone number and password. The menu button opens your sections; "Switch service" changes between your services; Settings > Language switches Swahili/English; Settings > Logout signs out. If a section is missing from your menu, your account has not been given that right: ask the business owner/administrator.';
        if ($user->seesAllAccounts()) {
            return $general . "\nPLATFORM ADMIN: you run the platform, not a shop, so you do not see any business's own sales, stock, customers or drivers. Everything is under Settings:"
                . "\n- \"Business Registrations\": new businesses that applied. Open one, check the details, then Approve (or Approve as requested) or Reject. Filter by Pending, Approved or Rejected. The applicant is told by text message."
                . "\n- \"Businesses & Plans\": every business with its plan and the date it runs until. Filter by Ending soon or Expired. To record that a business paid, open it and tap Record payment."
                . "\n- \"Plans & Prices\": set the price of each plan for 1, 3, 6 and 12 months; the prices show on the registration form."
                . "\n- SMS sender names: approve each business's text-message sender name."
                . "\nYou cannot answer questions about a business's own figures here; the owner sees those in their own app.";
        }
        $lines = [$general];
        foreach (self::entries() as $e) {
            if (self::applies($e, $user)) {
                $lines[] = $e['text'];
            }
        }

        return implode("\n", $lines);
    }

    /** @return array<int, array{id: string, en: string, sw: string}> how-to questions for the sections this person has */
    public static function suggestionsFor(User $user): array
    {
        // The platform admin has no shop: offer questions about running the platform, never the shop how-tos.
        if ($user->seesAllAccounts()) {
            return [
                ['id' => 'hg_start', 'en' => 'What can I do in this app?', 'sw' => 'Ninaweza kufanya nini kwenye programu hii?'],
                ['id' => 'hg_s_reg', 'en' => 'How do I approve a new business?', 'sw' => 'Ninaidhinishaje biashara mpya?'],
                ['id' => 'hg_s_pay', 'en' => 'How do I record a business payment?', 'sw' => 'Ninarekodije malipo ya biashara?'],
                ['id' => 'hg_s_plan', 'en' => 'How do I set plan prices?', 'sw' => 'Ninaweka vipi bei za mipango?'],
            ];
        }

        $all = [
            ['hg_start', 'What can I do in this app?', 'Ninaweza kufanya nini kwenye programu hii?', null],
            ['hg_sale', 'How do I record a sale?', 'Ninarekodije mauzo?', fn () => $user->canUseService('inventory') && $user->hasInventoryPermission('inv_create_sales')],
            ['hg_product', 'How do I add a product?', 'Ninaongezaje bidhaa?', fn () => $user->canUseService('inventory') && ($user->hasInventoryPermission('inv_manage_products') || $user->hasInventoryPermission('inv_create_products'))],
            ['hg_debt', 'How do I record an old debt?', 'Ninarekodije deni la zamani?', fn () => $user->canUseService('inventory') && $user->hasInventoryPermission('inv_view_credit')],
            ['hg_driver', 'How do I add a driver?', 'Ninaongezaje dereva?', fn () => $user->canUseService('transport') && (strtolower((string) $user->role) === 'admin' || $user->hasExplicitGrant('manage_drivers_transport'))],
            ['hg_pay', 'How do I record a driver payment?', 'Ninarekodije malipo ya dereva?', fn () => $user->canUseService('transport') && (strtolower((string) $user->role) === 'admin' || $user->hasExplicitGrant('manage_payments_transport'))],
            ['hg_tenant', 'How do I add a tenant and a lease?', 'Ninaongezaje mpangaji na mkataba?', fn () => $user->canUseService('rental') && (in_array(strtolower((string) $user->role), ['admin', 'landlord'], true) || $user->hasExplicitGrant('onboard_tenants_rental'))],
        ];
        $out = [];
        foreach ($all as [$id, $en, $sw, $when]) {
            if ($when === null || $when()) {
                $out[] = ['id' => $id, 'en' => $en, 'sw' => $sw];
            }
        }

        return $out;
    }
}

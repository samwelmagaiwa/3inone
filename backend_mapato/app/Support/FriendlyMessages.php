<?php

namespace App\Support;

/**
 * Plain-words messages for the person using the app, in both languages, in the form the apps read: "Swahili sentence. / English sentence."
 * (the app shows the half that is read). Two jobs:
 *
 *  - what is wrong with something that was typed or chosen (a missing name, a SKU in use, a date that is not a date): built from the
 *    rule that failed and the NAME of the field as a person says it ("selling price", not "selling_price"), see rule() and label();
 *  - what went wrong with an operation (a sale already cancelled, a customer who still owes): text() improves a message a controller
 *    wrote in English only, matched by its exact words, so no call site needs touching and anything unknown is left as it was.
 */
final class FriendlyMessages
{
    /** attribute => [swahili, english] (as a person says it, lower case). */
    private const LABELS = [
        'name' => ['jina', 'name'], 'description' => ['maelezo', 'description'], 'note' => ['maelezo ya ziada', 'note'], 'notes' => ['maelezo ya ziada', 'note'],
        'sku' => ['SKU', 'SKU'], 'barcode' => ['barcode', 'barcode'], 'category' => ['aina', 'category'], 'category_id' => ['aina', 'category'], 'brand_id' => ['chapa', 'brand'],
        'cost_price' => ['bei ya kununua', 'cost price'], 'selling_price' => ['bei ya kuuza', 'selling price'], 'price' => ['bei', 'price'], 'unit_price' => ['bei ya kuuza', 'selling price'],
        'unit_cost_snapshot' => ['bei ya kununua', 'cost price'], 'retail_price' => ['bei ya rejareja', 'retail price'], 'wholesale_price' => ['bei ya jumla', 'wholesale price'],
        'quantity' => ['idadi', 'quantity'], 'qty' => ['idadi', 'quantity'], 'min_stock' => ['kiwango cha chini cha stoo', 'minimum stock'], 'unit' => ['kipimo', 'unit'],
        'unit_factor' => ['idadi kwa kipimo', 'amount per unit'], 'factor' => ['idadi', 'amount'], 'measure' => ['jinsi ya kupima', 'way of measuring'], 'tax_percent' => ['VAT', 'VAT rate'],
        'status' => ['hali', 'status'], 'amount' => ['kiasi', 'amount'], 'total' => ['jumla', 'total'], 'subtotal' => ['jumla ndogo', 'sub-total'], 'discount' => ['punguzo', 'discount'],
        'discount_reason' => ['sababu ya punguzo', 'reason for the discount'], 'paid_total' => ['kiasi kilicholipwa', 'amount paid'], 'paid_amount' => ['kiasi kilicholipwa', 'amount paid'],
        'payment_status' => ['hali ya malipo', 'payment status'], 'payment_method' => ['njia ya kulipa', 'payment method'], 'method' => ['njia ya kulipa', 'payment method'],
        'reference' => ['namba ya muamala', 'reference number'], 'reason' => ['sababu', 'reason'], 'paid_at' => ['tarehe ya malipo', 'payment date'],
        'customer_id' => ['mteja', 'customer'], 'customer_name' => ['jina la mteja', "customer's name"], 'customer_phone' => ['simu ya mteja', "customer's phone"],
        'product_id' => ['bidhaa', 'product'], 'supplier_id' => ['msambazaji', 'supplier'], 'staff_id' => ['aliyemhudumia mteja', 'person who served'], 'branch_id' => ['tawi', 'branch'],
        'sale_id' => ['mauzo', 'sale'], 'items' => ['bidhaa za mauzo', 'items of the sale'], 'payments' => ['malipo', 'payments'], 'lines' => ['mistari', 'lines'], 'units' => ['njia za kuuza', 'selling units'],
        'phone' => ['namba ya simu', 'phone number'], 'phone_number' => ['namba ya simu', 'phone number'], 'email' => ['barua pepe', 'email address'], 'address' => ['anwani', 'address'],
        'password' => ['nenosiri', 'password'], 'password_confirmation' => ['uthibitisho wa nenosiri', 'password confirmation'], 'code' => ['namba ya uthibitisho', 'code'],
        'expense_date' => ['tarehe ya matumizi', 'expense date'], 'date' => ['tarehe', 'date'], 'from' => ['tarehe ya kuanza', 'start date'], 'to' => ['tarehe ya mwisho', 'end date'],
        'started_on' => ['tarehe ya kuanza', 'start date'], 'due_on' => ['tarehe ya mwisho ya kulipa', 'due date'], 'due_date' => ['tarehe ya kulipa', 'pay-by date'],
        'supplier' => ['msambazaji', 'supplier'], 'kind' => ['aina', 'kind'], 'type' => ['aina', 'type'], 'month' => ['mwezi', 'month'], 'profit_target' => ['lengo la faida', 'profit target'],
        'credit_limit' => ['kikomo cha mkopo', 'credit limit'], 'terms_days' => ['siku za kulipa', 'days to pay'], 'duration_minutes' => ['muda (dakika)', 'time taken (minutes)'],
        'commission_percent' => ['asilimia ya kamisheni', 'commission percent'], 'commission_fixed' => ['kamisheni ya kudumu', 'fixed commission'], 'label' => ['jina la chaguo', 'label'],
        'logo' => ['nembo', 'logo'], 'receipt' => ['picha ya risiti', 'receipt photo'], 'photo' => ['picha', 'photo'], 'confirm' => ['uthibitisho', 'confirmation'], 'tin' => ['TIN', 'TIN'],
        'role' => ['wadhifa', 'role'], 'permissions' => ['ruhusa', 'permissions'], 'services' => ['huduma', 'services'], 'rebook_weeks' => ['wiki za kurudi', 'weeks to come back'],
        'cancel_hours' => ['saa za kughairi', 'hours to cancel'], 'booking_slug' => ['anwani ya miadi', 'booking address'], 'birthday_text' => ['ujumbe wa siku ya kuzaliwa', 'birthday message'],
        'opening_balance' => ['salio la kuanzia', 'opening balance'], 'counted' => ['idadi iliyohesabiwa', 'counted amount'], 'title' => ['kichwa', 'title'], 'per_page' => ['idadi kwa ukurasa', 'items per page'],
    ];

    /** Fields the person CHOOSES from a list or picks (the message then says "Choose", not "Enter"). */
    private const CHOOSE = ['status', 'payment_status', 'payment_method', 'method', 'category', 'kind', 'type', 'measure', 'role', 'unit', 'month', 'date', 'expense_date', 'started_on', 'due_on', 'due_date', 'paid_at', 'from', 'to'];

    /** @return array{0: string, 1: string} [swahili, english] of the field as a person says it */
    public static function label(string $attribute): array
    {
        $key = self::lastPart($attribute);
        if (isset(self::LABELS[$key])) {
            return self::LABELS[$key];
        }
        $plain = str_replace('_', ' ', preg_replace('/_id$/', '', $key) ?? $key);

        return [$plain, $plain];
    }

    private static function lastPart(string $attribute): string
    {
        $parts = explode('.', $attribute);

        return end($parts) ?: $attribute;
    }

    /** "Line 2: " for a row of a list ("items.1.quantity"), so the person knows which row is meant. */
    private static function rowPrefix(string $attribute): array
    {
        if (preg_match('/^[a-z_]+\.(\d+)\./i', $attribute, $m) === 1) {
            $n = (int) $m[1] + 1;

            return ["Mstari {$n}: ", "Line {$n}: "];
        }

        return ['', ''];
    }

    private static function up(string $s): string
    {
        return mb_strtoupper(mb_substr($s, 0, 1)) . mb_substr($s, 1);
    }

    private static function plain(mixed $v): string
    {
        $text = is_scalar($v) ? (string) $v : '';
        $text = trim(str_replace(' / ', ' - ', $text));

        return mb_strlen($text) > 60 ? mb_substr($text, 0, 57) . '…' : $text;
    }

    /**
     * The message for a failed validation rule, or null when the rule is not one this knows (the framework's own text is then used).
     *
     * @param  array<int, mixed>  $parameters  the rule's parameters (min:3 -> ['3'])
     * @param  string  $type  numeric | string | array | file (what the rule measured)
     */
    public static function rule(string $attribute, string $rule, array $parameters, string $type, mixed $value, ?array $otherLabel = null): ?string
    {
        [$sw, $en] = self::label($attribute);
        [$psw, $pen] = self::rowPrefix($attribute);
        $rule = strtolower($rule);
        $p0 = $parameters[0] ?? '';
        $choose = in_array(self::lastPart($attribute), self::CHOOSE, true) || str_ends_with(self::lastPart($attribute), '_id');
        $val = self::plain($value);
        $pair = null;

        switch ($rule) {
            case 'required': case 'filled': case 'present': case 'required_if': case 'required_unless': case 'required_with': case 'required_with_all':
            case 'required_without': case 'required_without_all': case 'required_array_keys':
                if ($type === 'array') {
                    $pair = ["Ongeza angalau kimoja kwenye {$sw}.", "Add at least one to the {$en}."];
                } else {
                    $pair = $choose ? ['Chagua ' . $sw . '.', "Choose the {$en}."] : ['Andika ' . $sw . '.', "Enter the {$en}."];
                }
                break;
            case 'string':
                $pair = [self::up($sw) . ' lazima iwe maandishi.', "The {$en} must be text."];
                break;
            case 'integer':
                $pair = [self::up($sw) . ' lazima iwe namba nzima (bila nukta).', "The {$en} must be a whole number (no decimals)."];
                break;
            case 'numeric': case 'decimal':
                $pair = [self::up($sw) . ' lazima iwe namba.', "The {$en} must be a number."];
                break;
            case 'boolean': case 'bool':
                $pair = [self::up($sw) . ' lazima iwe ndiyo au hapana.', "The {$en} must be yes or no."];
                break;
            case 'array':
                $pair = [self::up($sw) . ' si sahihi.', "The {$en} is not valid."];
                break;
            case 'min': case 'min_digits':
                $pair = match ($type) {
                    'string' => [self::up($sw) . " lazima iwe na angalau herufi {$p0}.", "The {$en} must have at least {$p0} characters."],
                    'array' => ["Weka angalau {$p0} kwenye {$sw}.", "Add at least {$p0} to the {$en}."],
                    'file' => [self::up($sw) . " ni ndogo mno (angalau KB {$p0}).", "The {$en} is too small (at least {$p0} KB)."],
                    default => [self::up($sw) . " haiwezi kuwa chini ya {$p0}.", "The {$en} cannot be less than {$p0}."],
                };
                break;
            case 'max': case 'max_digits':
                $pair = match ($type) {
                    'string' => [self::up($sw) . " haiwezi kuwa na herufi zaidi ya {$p0}.", "The {$en} cannot have more than {$p0} characters."],
                    'array' => ["Huwezi kuweka zaidi ya {$p0} kwenye {$sw}.", "You cannot add more than {$p0} to the {$en}."],
                    'file' => [self::up($sw) . " ni kubwa mno (isizidi KB {$p0}).", "The {$en} is too large (not over {$p0} KB)."],
                    default => [self::up($sw) . " haiwezi kuzidi {$p0}.", "The {$en} cannot be more than {$p0}."],
                };
                break;
            case 'between':
                $b = $parameters[1] ?? '';
                $pair = $type === 'string'
                    ? [self::up($sw) . " lazima iwe na herufi kati ya {$p0} na {$b}.", "The {$en} must have between {$p0} and {$b} characters."]
                    : [self::up($sw) . " lazima iwe kati ya {$p0} na {$b}.", "The {$en} must be between {$p0} and {$b}."];
                break;
            case 'digits':
                $pair = [self::up($sw) . " lazima iwe na tarakimu {$p0} kamili.", "The {$en} must be exactly {$p0} digits."];
                break;
            case 'size':
                $pair = [self::up($sw) . " lazima iwe {$p0}.", "The {$en} must be {$p0}."];
                break;
            case 'gt': case 'gte': case 'lt': case 'lte':
                $other = $otherLabel ?? [(string) $p0, (string) $p0];
                $more = in_array($rule, ['gt', 'gte'], true);
                $orEqual = in_array($rule, ['gte', 'lte'], true);
                $pair = $more
                    ? [self::up($sw) . ' lazima iwe ' . ($orEqual ? 'sawa au kubwa kuliko ' : 'kubwa kuliko ') . $other[0] . '.', "The {$en} must be " . ($orEqual ? 'at least ' : 'more than ') . $other[1] . '.']
                    : [self::up($sw) . ' lazima iwe ' . ($orEqual ? 'sawa au ndogo kuliko ' : 'ndogo kuliko ') . $other[0] . '.', "The {$en} must be " . ($orEqual ? 'at most ' : 'less than ') . $other[1] . '.'];
                break;
            case 'in': case 'not_in': case 'enum':
                $pair = [self::up($sw) . ' uliyochagua si sahihi.', "The {$en} you chose is not valid."];
                break;
            case 'exists':
                $pair = [self::up($sw) . ' uliyochagua haipo (huenda ilifutwa). Chagua tena.', "The {$en} you chose does not exist (it may have been deleted). Choose again."];
                break;
            case 'unique':
                $pair = [self::up($sw) . ($val !== '' ? " '{$val}'" : '') . ' tayari inatumika. Tumia nyingine.', "The {$en}" . ($val !== '' ? " '{$val}'" : '') . ' is already in use. Use a different one.'];
                break;
            case 'date': case 'date_format': case 'date_equals':
                $pair = [self::up($sw) . ' si tarehe sahihi (mfano 2026-11-05).', "The {$en} is not a valid date (for example 2026-11-05)."];
                break;
            case 'after': case 'after_or_equal': case 'before': case 'before_or_equal':
                $other = $otherLabel ?? [(string) $p0, (string) $p0];
                $late = in_array($rule, ['after', 'after_or_equal'], true);
                $pair = $late
                    ? [self::up($sw) . ' haiwezi kuwa kabla ya ' . $other[0] . '.', "The {$en} cannot be before " . $other[1] . '.']
                    : [self::up($sw) . ' haiwezi kuwa baada ya ' . $other[0] . '.', "The {$en} cannot be after " . $other[1] . '.'];
                break;
            case 'email':
                $pair = [self::up($sw) . ' si anwani sahihi ya barua pepe (mfano jina@mfano.com).', "The {$en} is not a valid email address (for example name@example.com)."];
                break;
            case 'regex': case 'not_regex': case 'alpha': case 'alpha_num': case 'alpha_dash': case 'ascii': case 'lowercase': case 'uppercase': case 'uuid': case 'url': case 'ip': case 'json':
                $pair = [self::up($sw) . ' haiko katika muundo sahihi.', "The {$en} is not in the right format."];
                break;
            case 'confirmed': case 'same':
                $pair = [self::up($sw) . ' mbili hazifanani. Ziandike tena.', "The two {$en} entries do not match. Type them again."];
                break;
            case 'different':
                $pair = [self::up($sw) . ' lazima iwe tofauti na ya awali.', "The {$en} must be different from the one before."];
                break;
            case 'accepted': case 'accepted_if':
                $pair = ["Lazima ukubali {$sw}.", "You must accept the {$en}."];
                break;
            case 'prohibited': case 'prohibits': case 'missing':
                $pair = [self::up($sw) . ' hairuhusiwi hapa.', "The {$en} is not allowed here."];
                break;
            case 'distinct':
                $pair = [self::up($sw) . ' imerudiwa. Kila moja lazima iwe tofauti.', "The {$en} has a duplicate. Each one must be different."];
                break;
            case 'image': case 'mimes': case 'mimetypes': case 'extensions':
                $pair = [self::up($sw) . ' lazima iwe picha (jpg au png).', "The {$en} must be a photo (jpg or png)."];
                break;
            case 'file': case 'uploaded':
                $pair = [self::up($sw) . ' haikupakiwa. Jaribu tena.', "The {$en} could not be uploaded. Try again."];
                break;
        }

        return $pair === null ? null : ($psw . $pair[0]) . ' / ' . ($pen . $pair[1]);
    }

    // ------------------------------------------------------------------ what went wrong with an operation

    /** English message (exactly as a controller wrote it) => "Swahili. / English." in plain words, saying what to do next. */
    private const OPERATIONS = [
        // not found
        'API endpoint not found' => ['Ukurasa huu haupo kwenye seva. Sasisha programu na ujaribu tena.', 'This page does not exist on the server. Update the app and try again.'],
        'Not found' => ['Haikupatikana. Huenda ilifutwa au si ya biashara hii.', 'It was not found. It may have been deleted, or it is not in this business.'],
        'Product not found' => ['Bidhaa haikupatikana. Huenda ilifutwa.', 'The product was not found. It may have been deleted.'],
        'Sale not found' => ['Mauzo hayakupatikana.', 'The sale was not found.'],
        'Client not found' => ['Mteja hakupatikana.', 'The client was not found.'],
        'Appointment not found' => ['Miadi haikupatikana. Huenda ilifutwa.', 'The appointment was not found. It may have been deleted.'],
        'Branch not found' => ['Tawi halikupatikana.', 'The branch was not found.'],
        'Entry not found' => ['Rekodi haikupatikana.', 'That entry was not found.'],
        'Equipment not found' => ['Kifaa hakikupatikana.', 'The equipment was not found.'],
        'Photo not found' => ['Picha haikupatikana.', 'The photo was not found.'],
        'Service not found' => ['Huduma haikupatikana. Huenda ilifutwa.', 'The service was not found. It may have been deleted.'],
        'Shift not found' => ['Zamu haikupatikana.', 'The shift was not found.'],
        'Voucher not found' => ['Vocha haikupatikana.', 'The voucher was not found.'],
        'That item does not exist' => ['Bidhaa hiyo haipo.', 'That item does not exist.'],
        'Unknown barcode' => ['Barcode hii haijulikani. Hakuna bidhaa yenye namba hii.', 'This barcode is not known. No item has this number.'],
        'Unknown report' => ['Ripoti hii haijulikani.', 'This report is not known.'],
        'Unknown kind' => ['Aina hii haijulikani.', 'This kind is not known.'],
        'Not in the Trash' => ['Hii haipo Takataka.', 'It is not in the Trash.'],
        // who may
        'Unauthorized action.' => ['Huruhusiwi kufanya hili. Muulize mmiliki.', 'You are not allowed to do this. Ask the owner.'],
        'Only admins may force-delete a brand with products.' => ['Chapa yenye bidhaa inaweza kufutwa na msimamizi tu.', 'Only an admin can delete a brand that still has products.'],
        'Only admins may force-delete a category with products.' => ['Aina yenye bidhaa inaweza kufutwa na msimamizi tu.', 'Only an admin can delete a category that still has products.'],
        'Only admins may force-delete a supplier with open invoices.' => ['Msambazaji mwenye ankara wazi anaweza kufutwa na msimamizi tu.', 'Only an admin can delete a supplier who still has open invoices.'],
        'You can only attach a receipt to your own expense.' => ['Unaweza kuweka picha ya risiti kwenye matumizi yako mwenyewe tu.', 'You can only attach a receipt photo to an expense you recorded yourself.'],
        'You can only close your own cash session.' => ['Unaweza kufunga zamu ya pesa uliyofungua mwenyewe tu.', 'You can only close a cash session you opened yourself.'],
        'You can only delete your own expenses.' => ['Unaweza kufuta matumizi uliyoandika mwenyewe tu. Muulize mmiliki.', 'You can only delete expenses you recorded yourself. Ask the owner.'],
        'You can only edit your own expenses.' => ['Unaweza kubadilisha matumizi uliyoandika mwenyewe tu. Muulize mmiliki.', 'You can only edit expenses you recorded yourself. Ask the owner.'],
        'Only super admin can view users grouped by service.' => ['Huruhusiwi kuona ukurasa huu.', 'You are not allowed to see this page.'],
        // sales and payments
        'Customer required for debt/partial' => ['Mauzo ya deni au ya kulipa sehemu yanahitaji mteja. Chagua au ongeza mteja kwanza.', 'A sale paid later or in part needs a customer. Choose or add a customer first.'],
        'Cannot pay a cancelled sale' => ['Mauzo haya yamefutwa, hayawezi kulipwa.', 'This sale was cancelled, so it cannot be paid.'],
        'Sale already cancelled' => ['Mauzo haya tayari yamefutwa.', 'This sale was already cancelled.'],
        'Sale is already fully paid' => ['Mauzo haya tayari yamelipwa yote. Hakuna deni.', 'This sale is already fully paid. Nothing is owed.'],
        'Quantity exceeds what is in stock' => ['Idadi inazidi kilichopo stoo. Punguza idadi.', 'The quantity is more than what is in stock. Reduce the quantity.'],
        'That unit is not available for this product' => ['Kipimo hiki hakipo kwa bidhaa hii. Chagua kingine.', 'This unit is not available for this product. Choose another.'],
        'That unit already exists for this product' => ['Kipimo hiki tayari kipo kwa bidhaa hii. Tumia jina tofauti.', 'This unit already exists for this product. Use a different name.'],
        'The base unit cannot be removed' => ['Kipimo kikuu hakiwezi kuondolewa. Unaweza kukibadilisha jina.', 'The main unit cannot be removed. You can rename it instead.'],
        'A special price needs a customer' => ['Bei maalum inahitaji mteja. Chagua mteja.', 'A special price needs a customer. Choose the customer.'],
        'Already reconciled' => ['Hii tayari imehakikiwa.', 'This was already reconciled.'],
        // cash, counts and forms with nothing in them
        'Session is closed' => ['Zamu ya pesa imefungwa. Fungua zamu mpya.', 'The cash session is closed. Open a new one.'],
        'Session is already closed' => ['Zamu hii ya pesa tayari imefungwa.', 'This cash session is already closed.'],
        'Nothing counted yet' => ['Bado hujahesabu kitu. Hesabu angalau bidhaa moja.', 'Nothing has been counted yet. Count at least one item.'],
        'Nothing to save' => ['Hakuna mabadiliko ya kuhifadhi.', 'There is nothing to save.'],
        'Nothing to update' => ['Hakuna mabadiliko ya kuhifadhi.', 'There is nothing to update.'],
        'No code supplied' => ['Andika au piga skani namba ya barcode.', 'Type or scan the barcode.'],
        // trash and delete rules
        'Customer has outstanding debt. Settle all balances first.' => ['Mteja huyu bado ana deni. Pokea malipo yote kwanza kabla ya kumwondoa.', 'This customer still owes money. Take all the payments first, then delete.'],
        'Customer has outstanding debt. Settle all balances first, or pass ?force=1.' => ['Mteja huyu bado ana deni. Pokea malipo yote kwanza kabla ya kumfuta.', 'This customer still owes money. Take all the payments first, then delete.'],
        'Product moved to the Trash' => ['Bidhaa imehamishiwa Takataka.', 'The product was moved to the Trash.'],
        'Moved to the Trash' => ['Imehamishiwa Takataka.', 'Moved to the Trash.'],
        'Customer moved to the Trash' => ['Mteja amehamishiwa Takataka.', 'The customer was moved to the Trash.'],
    ];

    /** The improved bilingual message for an English one, or null when none is known (patterns first, then exact words). */
    public static function text(string $english): ?string
    {
        $english = trim($english);
        if (isset(self::OPERATIONS[$english])) {
            return self::OPERATIONS[$english][0] . ' / ' . self::OPERATIONS[$english][1];
        }

        if (preg_match('/^Already (\w+)$/', $english, $m) === 1) {
            return "Hii tayari ina hali '{$m[1]}', hakuna cha kufanya. / This is already {$m[1]}, so there is nothing to do.";
        }
        if (preg_match('/^Customers still hold (\d+) crate\(s\) of this type\./', $english, $m) === 1) {
            return "Wateja bado wana makreti {$m[1]} ya aina hii. Rekodi kurudishwa kwake kwanza kabla ya kuizima. / Customers still hold {$m[1]} crate(s) of this type. Record their return before switching it off.";
        }
        if (preg_match('/^This customer is holding (\d+) crate\(s\)\./', $english, $m) === 1) {
            return "Mteja huyu ana makreti {$m[1]}. Rekodi amerudisha kwanza kabla ya kumwondoa. / This customer is holding {$m[1]} crate(s). Record their return first, then delete.";
        }

        return null;
    }
}

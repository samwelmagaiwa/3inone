<?php

namespace App\Support\Access;

use App\Models\User;

/**
 * The things a business owner can switch on or off for each person, in plain words and in one place.
 *
 * A module is one permission key the owner sees as a switch. The key is what the server enforces (routes, controllers) and what the
 * app shows or hides, so a switch that is off is off everywhere. What a role starts with is its defaults (User::roleDefaults); the owner
 * then adds to it or takes from it for one person (users.permissions and users.denied_permissions).
 */
final class Modules
{
    /** The salon's menu sections, each its own right: nothing is shown or opened just because another right happens to be held. */
    public const SALON = [
        'inv_salon_appointments', 'inv_salon_walkins', 'inv_salon_rebook', 'inv_salon_stylists', 'inv_salon_team',
        'inv_salon_feedback', 'inv_salon_equipment', 'inv_salon_branch_stock', 'inv_salon_insights', 'inv_salon_money',
        'inv_salon_reports', 'inv_salon_profit', 'inv_salon_payroll', 'inv_salon_cashbook', 'inv_salon_export', 'inv_salon_schedule',
        'inv_salon_devices',
    ];

    /**
     * The switches, grouped as the owner reads them. Each: key, group, English and Kiswahili names, and the services it applies to.
     *
     * @return array<int, array{key: string, group: string, en: string, sw: string, services: array<int, string>}>
     */
    public static function catalog(): array
    {
        $both = ['inventory', 'salon'];
        $salon = ['salon'];

        return [
            // ---- Goods and services
            ['key' => 'inv_view_products', 'group' => 'goods', 'en' => 'See services and goods', 'sw' => 'Kuona huduma na bidhaa', 'services' => $both],
            ['key' => 'inv_create_products', 'group' => 'goods', 'en' => 'Add new services, goods, categories and brands', 'sw' => 'Kuongeza huduma, bidhaa, makundi na chapa mpya', 'services' => $both],
            ['key' => 'inv_manage_products', 'group' => 'goods', 'en' => 'Change and delete services and goods, prices', 'sw' => 'Kubadilisha na kufuta huduma na bidhaa, bei', 'services' => $both],
            ['key' => 'inv_manage_stock', 'group' => 'goods', 'en' => 'Stock: receive, count, approve damages', 'sw' => 'Stoo: kupokea, kuhesabu, kuidhinisha hasara', 'services' => $both],
            ['key' => 'inv_report_damage', 'group' => 'goods', 'en' => 'Report damaged goods', 'sw' => 'Kuripoti bidhaa zilizoharibika', 'services' => $both],
            // ---- Selling
            ['key' => 'inv_create_sales', 'group' => 'selling', 'en' => 'Sell (the till)', 'sw' => 'Kuuza (kaunta)', 'services' => $both],
            ['key' => 'inv_manage_sales', 'group' => 'selling', 'en' => 'Change sales, take payments, see the sales of everyone', 'sw' => 'Kubadilisha mauzo, kupokea malipo, kuona mauzo ya wote', 'services' => $both],
            ['key' => 'inv_cancel_sales', 'group' => 'selling', 'en' => 'Delete (cancel) a sale', 'sw' => 'Kufuta mauzo', 'services' => $both],
            ['key' => 'inv_return_sales', 'group' => 'selling', 'en' => 'Return goods and approve returns', 'sw' => 'Kurudisha bidhaa na kuidhinisha marejesho', 'services' => $both],
            ['key' => 'inv_salon_appointments', 'group' => 'selling', 'en' => 'Appointments', 'sw' => 'Miadi', 'services' => $salon],
            ['key' => 'inv_salon_walkins', 'group' => 'selling', 'en' => 'Walk-ins queue', 'sw' => 'Wanaosubiri', 'services' => $salon],
            ['key' => 'inv_salon_rebook', 'group' => 'selling', 'en' => 'Come-back reminders', 'sw' => 'Vikumbusho vya kurudi', 'services' => $salon],
            // ---- Money
            ['key' => 'inv_view_credit', 'group' => 'money', 'en' => 'Clients and credit, debts', 'sw' => 'Wateja na madeni', 'services' => $both],
            ['key' => 'inv_view_cash', 'group' => 'money', 'en' => 'Daily cash', 'sw' => 'Fedha ya kila siku', 'services' => $both],
            ['key' => 'inv_view_expenses', 'group' => 'money', 'en' => 'See spending', 'sw' => 'Kuona matumizi', 'services' => $both],
            ['key' => 'inv_manage_expenses', 'group' => 'money', 'en' => 'Record spending', 'sw' => 'Kurekodi matumizi', 'services' => $both],
            ['key' => 'inv_approve_expenses', 'group' => 'money', 'en' => 'Approve or turn down spending others recorded', 'sw' => 'Kuidhinisha au kukataa matumizi yaliyorekodiwa na wengine', 'services' => $salon],
            ['key' => 'inv_salon_money', 'group' => 'money', 'en' => 'Money pages: income, spending and money received', 'sw' => 'Kurasa za fedha: mapato, matumizi na pesa zilizopokelewa', 'services' => $salon],
            ['key' => 'inv_salon_profit', 'group' => 'money', 'en' => 'See profit, commissions and salaries paid', 'sw' => 'Kuona faida, kamisheni na mishahara iliyolipwa', 'services' => $salon],
            ['key' => 'inv_salon_payroll', 'group' => 'money', 'en' => 'Payroll: pay, commission and payments to staff', 'sw' => 'Mishahara: malipo, kamisheni na malipo kwa wafanyakazi', 'services' => $salon],
            ['key' => 'inv_salon_cashbook', 'group' => 'money', 'en' => 'Cashbook', 'sw' => 'Kitabu cha pesa', 'services' => $salon],
            ['key' => 'inv_salon_export', 'group' => 'money', 'en' => 'Export reports (only what the rights above allow)', 'sw' => 'Kuhamisha ripoti (zile tu ambazo haki zingine zinaruhusu)', 'services' => $salon],
            // ---- Reports and understanding the business
            ['key' => 'inv_view_reports', 'group' => 'reports', 'en' => 'Reports, profit and the monthly report', 'sw' => 'Ripoti, faida na ripoti ya mwezi', 'services' => $both],
            ['key' => 'inv_view_reminders', 'group' => 'reports', 'en' => 'Reminders', 'sw' => 'Vikumbusho', 'services' => $both],
            ['key' => 'inv_salon_reports', 'group' => 'reports', 'en' => 'The Salon tab of Reports', 'sw' => 'Kichupo cha Saluni kwenye Ripoti', 'services' => $salon],
            ['key' => 'inv_salon_insights', 'group' => 'reports', 'en' => 'Insights (trends, best days and hours)', 'sw' => 'Mwenendo (siku na saa bora)', 'services' => $salon],
            ['key' => 'inv_salon_stylists', 'group' => 'reports', 'en' => 'How each stylist did', 'sw' => 'Matokeo ya kila mhudumu', 'services' => $salon],
            ['key' => 'inv_salon_feedback', 'group' => 'reports', 'en' => 'Client feedback', 'sw' => 'Maoni ya wateja', 'services' => $salon],
            // ---- People and the place
            ['key' => 'inv_salon_team', 'group' => 'people', 'en' => 'Team: attendance, days off, payroll', 'sw' => 'Timu: mahudhurio, siku za mapumziko, mishahara', 'services' => $salon],
            ['key' => 'inv_salon_schedule', 'group' => 'people', 'en' => 'Set working days, hours and days off', 'sw' => 'Kupanga siku, saa za kazi na mapumziko', 'services' => $salon],
            ['key' => 'inv_salon_devices', 'group' => 'people', 'en' => 'Offices, staff devices and the attendance log', 'sw' => 'Ofisi, vifaa vya wafanyakazi na kumbukumbu za mahudhurio', 'services' => $salon],
            ['key' => 'inv_salon_equipment', 'group' => 'people', 'en' => 'Equipment', 'sw' => 'Vifaa', 'services' => $salon],
            ['key' => 'inv_salon_branch_stock', 'group' => 'people', 'en' => 'Goods by branch', 'sw' => 'Bidhaa kwa tawi', 'services' => $salon],
            ['key' => 'inv_view_purchasing', 'group' => 'people', 'en' => 'Purchasing and suppliers', 'sw' => 'Manunuzi na wasambazaji', 'services' => ['inventory']],
            ['key' => 'inv_view_crates', 'group' => 'people', 'en' => 'Crates and empties', 'sw' => 'Makreti', 'services' => ['inventory']],
            ['key' => 'inv_manage_settings', 'group' => 'people', 'en' => 'Business settings, branches, staff rights', 'sw' => 'Mipangilio ya biashara, matawi, haki za wafanyakazi', 'services' => $both],
        ];
    }

    /** The switches that apply to the services of whoever is being configured. */
    public static function forServices(array $services): array
    {
        return array_values(array_filter(self::catalog(), fn (array $m) => array_intersect($m['services'], $services) !== []));
    }

    /**
     * Everything the owner needs to draw the access screen for one person: each switch with whether it is on, where that comes from
     * (their role, the owner's addition) and whether the owner has taken it back.
     *
     * @return array<int, array<string, mixed>>
     */
    public static function stateFor(User $person, array $services): array
    {
        $defaults = User::roleDefaults((string) $person->role);
        $grants = is_array($person->permissions) ? $person->permissions : [];
        $denied = is_array($person->denied_permissions) ? $person->denied_permissions : [];

        return array_map(function (array $m) use ($defaults, $grants, $denied, $person) {
            $fromRole = in_array($m['key'], $defaults, true);
            $added = in_array($m['key'], $grants, true);
            $taken = in_array($m['key'], $denied, true);

            return $m + [
                'on' => $person->hasInventoryPermission($m['key']),
                'from_role' => $fromRole,
                'added' => $added,
                'taken_back' => $taken,
            ];
        }, self::forServices($services));
    }

    /**
     * Turn the switches the owner left on into what is stored: grants (on, but not what the role gives) and denials (off, but the role
     * gives it). Keys that are not switches for these services are ignored, so nothing else can be changed through here.
     *
     * @param  array<int, string>  $on  the keys left switched on
     * @return array{permissions: array<int, string>, denied_permissions: array<int, string>}
     */
    public static function split(string $role, array $services, array $on): array
    {
        $defaults = User::roleDefaults($role);
        $keys = array_column(self::forServices($services), 'key');
        $grants = [];
        $denied = [];
        foreach ($keys as $key) {
            $isOn = in_array($key, $on, true);
            $given = in_array($key, $defaults, true);
            if ($isOn && !$given) {
                $grants[] = $key;
            } elseif (!$isOn && $given) {
                $denied[] = $key;
            }
        }

        return ['permissions' => $grants, 'denied_permissions' => $denied];
    }
}

<?php

/*
| What kind of inventory business is this?
|
| The owner picks one when registering (and can change it later in the business profile). It does not
| lock anything and it moves no data: it only decides what a NEW business's inventory starts with --
| a few depot settings, written once into that business's own inventory_settings (see
| App\Support\InventoryDefaults). Every one of those settings can still be changed afterwards.
|
| `depot` is what the platform did before types existed (beverage depot: crates and empties, one
| price per product). The platform defaults in InventoryDefaults::SETTINGS ARE the depot, so an
| existing business -- and a depot -- needs no preset at all and behaves exactly as it always did.
|
|   use_crates   returnable packaging: the crates menu, crate deposits and the "empties" step at checkout
|   sale_tier    which price the till uses: `product` = the product's own price (the depot way),
|                `retail` / `wholesale` = the selling unit's price for that tier
*/

return [

    /** In the order the app lists them. */
    'types' => ['retail', 'wholesale', 'mixed', 'depot'],

    /** Settings that differ from the platform defaults (= the depot). Only these are written. */
    'presets' => [
        'depot' => [],
        'wholesale' => ['use_crates' => '0', 'sale_tier' => 'wholesale'],
        'retail' => ['use_crates' => '0', 'sale_tier' => 'retail'],
        'mixed' => ['use_crates' => '0', 'sale_tier' => 'retail'],
    ],

];

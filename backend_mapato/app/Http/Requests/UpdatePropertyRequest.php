<?php

namespace App\Http\Requests;

use App\Rules\UserInAccount;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdatePropertyRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'name' => ['sometimes', 'string', 'max:255'],
            'property_type' => [
                'sometimes',
                Rule::in([
                    'apartment',
                    'rental_compound',
                    'standalone_house',
                    'hostel',
                    'commercial_building',
                    'mixed_use',
                    'office_space',
                    'shop_units'
                ])
            ],
            'region' => ['sometimes', 'string', 'max:100'],
            'district' => ['sometimes', 'string', 'max:100'],
            'ward' => ['nullable', 'string', 'max:100'],
            'street' => ['nullable', 'string', 'max:255'],
            'address' => ['sometimes', 'string', 'max:500'],
            'description' => ['nullable', 'string', 'max:1000'],
            'billing_cycle' => ['sometimes', Rule::in(['monthly', 'quarterly', 'yearly'])],
            'currency' => ['sometimes', 'string', 'max:10'],
            'status' => ['sometimes', Rule::in(['active', 'inactive', 'under_maintenance', 'archived'])],
            'total_units' => ['sometimes', 'integer', 'min:0'],
            'number_of_blocks' => ['sometimes', 'integer', 'min:1'],
            'caretaker_id' => ['nullable', new UserInAccount(
                $this->user(),
                \App\Models\Rental\Property::withTrashed()->whereKey($this->route('id'))->value('caretaker_id')
            )],
            'default_rent_amount' => [
                'nullable', 
                'numeric', 
                'min:0',
                function ($attribute, $value, $fail) {
                    $propertyId = $this->route('id');
                    if ($propertyId) {
                        $currentSum = \App\Models\Rental\House::where('property_id', $propertyId)->sum('rent_amount');
                        if ($value < $currentSum) {
                            $fail("The property rent target cannot be less than the sum of existing houses' rent (" . number_format($currentSum, 2) . ").");
                        }
                    }
                }
            ],
            'default_deposit_amount' => ['nullable', 'numeric', 'min:0'],
            'utility_billing_enabled' => ['sometimes', 'boolean'],
            'cover_image' => ['nullable', 'image', 'mimes:jpeg,png,jpg,gif', 'max:5000'],
        ];
    }
}
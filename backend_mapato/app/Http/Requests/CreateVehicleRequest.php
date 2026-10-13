<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Contracts\Validation\Validator;
use Illuminate\Http\Exceptions\HttpResponseException;
use App\Helpers\ResponseHelper;
use App\Rules\PerBusiness;

class CreateVehicleRequest extends FormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     */
    public function authorize(): bool
    {
        // Allow for now since we're bypassing auth temporarily
        return true;
    }

    /**
     * Get the validation rules that apply to the request.
     */
    /**
     * Plates are stored in capitals, so they are checked in capitals too (otherwise "t123abc"
     * would slip past a check against "T123ABC" on a case-sensitive database).
     */
    protected function prepareForValidation(): void
    {
        if (is_string($this->input('plate_number'))) {
            $this->merge(['plate_number' => strtoupper(trim($this->input('plate_number')))]);
        }
    }

    public function rules(): array
    {
        return [
            'name' => 'required|string|max:255',
            'type' => 'required|in:bajaji,pikipiki,gari',
            // Unique inside this business only: another business may have its own vehicle with
            // the same plate (one sold from a business to another, for instance).
            'plate_number' => ['required', 'string', 'max:50', PerBusiness::unique('devices', 'plate_number')],
            'description' => 'nullable|string|max:500',
            'driver_id' => 'nullable|uuid|exists:users,id',
        ];
    }

    /**
     * Get custom validation messages.
     */
    public function messages(): array
    {
        return [
            'name.required' => 'Jina la gari ni lazima',
            'name.string' => 'Jina la gari lazima liwe maandishi',
            'name.max' => 'Jina la gari haliwezi kuwa na herufi zaidi ya 255',
            
            'type.required' => 'Aina ya gari ni lazima',
            'type.in' => 'Aina ya gari lazima iwe bajaji, pikipiki, au gari',
            
            'plate_number.required' => 'Namba ya gari ni lazima',
            'plate_number.string' => 'Namba ya gari lazima iwe maandishi',
            'plate_number.max' => 'Namba ya gari haiwezi kuwa na herufi zaidi ya 50',
            'plate_number.unique' => 'Namba ya gari hii tayari imetumika',
            
            'description.string' => 'Maelezo lazima yawe maandishi',
            'description.max' => 'Maelezo hayawezi kuwa na herufi zaidi ya 500',
            
            'driver_id.uuid' => 'Kitambulisho cha dereva si sahihi',
            'driver_id.exists' => 'Dereva hujulikani',
        ];
    }

    /**
     * Handle a failed validation attempt.
     */
    protected function failedValidation(Validator $validator)
    {
        throw new HttpResponseException(
            ResponseHelper::validationError($validator->errors(), 'Taarifa zilizowekwa si sahihi')
        );
    }

    /**
     * Get the plate number in uppercase
     */
    public function getPlateNumber(): string
    {
        return strtoupper($this->input('plate_number'));
    }

    /**
     * Get the vehicle name with type prefix if not already included
     */
    public function getVehicleName(): string
    {
        $name = $this->input('name');
        $type = $this->input('type');
        
        // If name doesn't contain the type, add it as prefix
        if (!str_contains(strtolower($name), $type)) {
            $typeDisplay = match($type) {
                'bajaji' => 'Bajaji',
                'pikipiki' => 'Pikipiki',
                'gari' => 'Gari',
                default => ucfirst($type)
            };
            return $typeDisplay . ' - ' . $name;
        }
        
        return $name;
    }
}
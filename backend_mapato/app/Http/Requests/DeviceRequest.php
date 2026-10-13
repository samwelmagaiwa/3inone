<?php

namespace App\Http\Requests;

use App\Rules\PerBusiness;
use Illuminate\Foundation\Http\FormRequest;

class DeviceRequest extends FormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     */
    public function authorize(): bool
    {
        return true;
    }

    /**
     * Get the validation rules that apply to the request.
     */
    public function rules(): array
    {
        $deviceId = $this->route('device') ?? $this->route('id');
        
        return [
            'name' => 'required|string|max:255',
            'type' => 'required|in:bajaji,pikipiki,gari',
            'plate_number' => [
                'required',
                'string',
                'max:20',
                'regex:/^[A-Z]{1,2}\s?\d{3}\s?[A-Z]{3}$/i',
                // Unique inside this business only (see PerBusiness).
                PerBusiness::unique('devices', 'plate_number', ignoreId: $deviceId),
            ],
            'description' => 'nullable|string|max:500',
        ];
    }

    /**
     * Get custom error messages for validation rules.
     */
    public function messages(): array
    {
        return [
            'name.required' => 'Jina la chombo linahitajika',
            'type.required' => 'Aina ya chombo inahitajika',
            'type.in' => 'Aina ya chombo si sahihi',
            'plate_number.required' => 'Nambari ya bango inahitajika',
            'plate_number.regex' => 'Nambari ya bango si sahihi (mfano: T123ABC)',
            'plate_number.unique' => 'Nambari ya bango tayari imetumika',
        ];
    }

    /**
     * Prepare the data for validation.
     */
    protected function prepareForValidation(): void
    {
        // Convert plate number to uppercase and remove extra spaces
        if ($this->has('plate_number')) {
            $this->merge([
                'plate_number' => strtoupper(preg_replace('/\s+/', ' ', trim($this->plate_number))),
            ]);
        }
    }
}
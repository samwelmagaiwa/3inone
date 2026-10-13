<?php

namespace App\Http\Requests;

use App\Rules\PerBusiness;
use App\Rules\UniquePhoneInBusiness;
use App\Support\Tenancy\TenantContext;
use Illuminate\Foundation\Http\FormRequest;

class RegisterDriverRequest extends FormRequest
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
        $owner = TenantContext::writeOwner();

        return [
            'name' => 'required|string|max:255',
            // The email is the sign-in name: unique across the platform. Phone and licence only
            // have to be unique inside this business.
            'email' => 'required|email|unique:users,email',
            'password' => 'required|string|min:8|confirmed',
            'phone' => ['required', 'string', 'max:20', new UniquePhoneInBusiness($owner)],
'license_number' => ['nullable', 'string', PerBusiness::unique('drivers', 'license_number', $owner)],
'license_expiry' => 'nullable|date|after:today',
            'address' => 'nullable|string|max:255',
            'emergency_contact' => 'nullable|string|max:20',
        ];
    }

    /**
     * Get custom error messages for validation rules.
     */
    public function messages(): array
    {
        return [
            'name.required' => 'Jina linahitajika',
            'email.required' => 'Barua pepe inahitajika',
            'email.email' => 'Barua pepe si sahihi',
            'email.unique' => 'Barua pepe tayari imetumika',
            'password.required' => 'Nenosiri linahitajika',
            'password.min' => 'Nenosiri lazima liwe na angalau herufi 8',
            'password.confirmed' => 'Nenosiri hazifanani',
            'phone.required' => 'Nambari ya simu inahitajika',
            'license_number.required' => 'Nambari ya leseni inahitajika',
            'license_number.unique' => 'Nambari ya leseni tayari imetumika',
            'license_expiry.required' => 'Tarehe ya kuisha kwa leseni inahitajika',
            'license_expiry.after' => 'Tarehe ya kuisha kwa leseni lazima iwe ya baadaye',
        ];
    }
}
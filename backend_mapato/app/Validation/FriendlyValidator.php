<?php

namespace App\Validation;

use App\Support\FriendlyMessages;
use Illuminate\Validation\Validator;

/**
 * The framework's validator, but a failed rule is explained in plain words, in both languages, by the NAME of the field as a person says
 * it ("Andika bei ya kuuza. / Enter the selling price.") instead of "The selling_price field is required.". A message a controller
 * or form request wrote itself always wins.
 */
class FriendlyValidator extends Validator
{
    protected function getMessage($attribute, $rule)
    {
        $framework = parent::getMessage($attribute, $rule);

        if ($this->hasCustomMessage($attribute, $rule)) {
            return $framework;
        }

        $name = $this->normalizeRule($rule);
        $parameters = [];
        foreach ($this->rules[$attribute] ?? [] as $r) {
            if (is_string($r) && $this->normalizeRule(explode(':', $r, 2)[0]) === $name) {
                $parameters = str_contains($r, ':') ? str_getcsv(explode(':', $r, 2)[1]) : [];
                break;
            }
        }

        $other = null;
        if (in_array(strtolower($name), ['gt', 'gte', 'lt', 'lte', 'after', 'after_or_equal', 'before', 'before_or_equal'], true) && isset($parameters[0]) && !is_numeric($parameters[0]) && array_key_exists($parameters[0], $this->data)) {
            $other = FriendlyMessages::label($parameters[0]);
        }

        $friendly = FriendlyMessages::rule($attribute, $name, $parameters, $this->getAttributeType($attribute), $this->getValue($attribute), $other);

        return $friendly ?? $framework;
    }

    private function normalizeRule(string $rule): string
    {
        return strtolower(preg_replace('/(?<!^)[A-Z]/', '_$0', $rule) ?? $rule);
    }

    private function hasCustomMessage(string $attribute, string $rule): bool
    {
        $lower = lcfirst($rule);
        foreach ($this->customMessages as $key => $_) {
            $k = (string) $key;
            if ($k === $lower || $k === strtolower($rule) || $k === "{$attribute}.{$lower}" || $k === "{$attribute}.{$rule}" || preg_match('/^' . str_replace('\*', '[^.]+', preg_quote($k, '/')) . '$/', "{$attribute}.{$lower}") === 1) {
                return true;
            }
        }

        return false;
    }
}

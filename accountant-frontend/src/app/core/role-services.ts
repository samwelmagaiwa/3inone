/**
 * Which services a person may use, decided exactly as the mobile app decides it (utils/role_services.dart):
 * what a super admin bound to them, else what their role implies. The server remains the judge; this only chooses where to send
 * the person after sign-in, and what to offer in the picker.
 */
export type ServiceKey = 'inventory' | 'salon' | 'rental' | 'transport';

/** The services this web app can work in. The others are used on the phone. */
export const WEB_SERVICES: ServiceKey[] = ['inventory', 'salon'];

export function servicesForRole(role: string): ServiceKey[] {
  switch (role.toLowerCase()) {
    case 'super_admin':
      return ['inventory', 'rental', 'transport', 'salon'];
    case 'admin':
    case 'administrator':
      return []; // must be bound by the platform owner: no implicit access
    case 'sales_officer':
    case 'manager':
    case 'operator':
      return ['inventory'];
    case 'hair_stylist':
    case 'nail_technician':
    case 'lash_makeup_artist':
    case 'accountant':
      return ['salon'];
    case 'driver':
      return ['transport'];
    case 'landlord':
    case 'caretaker':
    case 'tenant':
    case 'vendor':
      return ['rental'];
    default:
      return [];
  }
}

const KNOWN: ServiceKey[] = ['inventory', 'salon', 'rental', 'transport'];

/** Every service the person has: their bindings, else what the role implies (unknown names are ignored). */
export function allServices(bound: string[], role: string): ServiceKey[] {
  const own = bound.filter((s): s is ServiceKey => KNOWN.includes(s as ServiceKey));
  const list = own.length ? own : servicesForRole(role);
  return list.filter((s, i) => list.indexOf(s) === i);
}

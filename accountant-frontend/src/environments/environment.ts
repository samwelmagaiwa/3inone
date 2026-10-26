/**
 * The API is reached by a relative path, so the same build works everywhere: in Docker nginx sends /api to the backend, and
 * `npm start` does the same through proxy.conf.json. No address is baked into the build.
 */
export const environment = {
  appName: '3inone Accountant',
  apiUrl: '/api',
  /** The service used when the account does not say (a shop). */
  defaultService: 'inventory' as const,
};

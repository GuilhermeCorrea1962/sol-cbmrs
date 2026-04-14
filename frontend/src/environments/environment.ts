export const environment = {
  production: false,
  apiUrl: '/api',
  keycloak: {
    issuer: 'http://localhost:8180/realms/sol',
    redirectUri: 'http://localhost:4200/',
    clientId: 'sol-frontend',
    scope: 'openid profile email roles',
    responseType: 'code',
    showDebugInformation: true,
    requireHttps: false,
    useSilentRefresh: false,
    sessionChecksEnabled: false,
    clearHashAfterLogin: true,
    timeoutFactor: 0.75
  }
};

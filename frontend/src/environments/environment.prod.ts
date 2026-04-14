export const environment = {
  production: true,
  apiUrl: '/api',
  keycloak: {
    issuer: 'http://localhost:8180/realms/sol',
    redirectUri: window.location.origin + '/',
    clientId: 'sol-frontend',
    scope: 'openid profile email roles',
    responseType: 'code',
    showDebugInformation: false,
    requireHttps: false,
    useSilentRefresh: false,
    sessionChecksEnabled: false,
    clearHashAfterLogin: true,
    timeoutFactor: 0.75
  }
};

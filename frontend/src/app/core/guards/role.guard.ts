import { inject } from '@angular/core';
import { ActivatedRouteSnapshot, CanActivateFn, Router } from '@angular/router';
import { AuthService, SolRole } from '../services/auth.service';

/**
 * Guard de perfil (role-based access control).
 *
 * Uso nas rotas:
 *   data: { roles: ['ADMIN', 'ANALISTA'] }
 *   canActivate: [authGuard, roleGuard]
 *
 * Se o usuario nao possuir nenhum dos roles exigidos, e redirecionado
 * ao dashboard (que exibe o conteudo adequado ao seu perfil).
 * Se nenhum role for declarado em data.roles, o guard libera o acesso.
 */
export const roleGuard: CanActivateFn = (route: ActivatedRouteSnapshot) => {
  const auth = inject(AuthService);
  const router = inject(Router);

  const requiredRoles: SolRole[] = (route.data['roles'] as SolRole[]) ?? [];

  if (requiredRoles.length === 0 || auth.hasAnyRole(requiredRoles)) {
    return true;
  }

  return router.createUrlTree(['/app/dashboard']);
};

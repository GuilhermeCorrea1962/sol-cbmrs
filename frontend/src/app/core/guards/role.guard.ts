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
  const userRoles = auth.getUserRoles();
  const allowed = requiredRoles.length === 0 || auth.hasAnyRole(requiredRoles);

  // DEBUG temporario para diagnosticar bloqueios inesperados de rota.
  // Remover apos investigacao.
  console.log('[roleGuard]', {
    path: route.routeConfig?.path,
    required: requiredRoles,
    userRoles,
    allowed,
  });

  if (allowed) return true;
  return router.createUrlTree(['/app/dashboard']);
};

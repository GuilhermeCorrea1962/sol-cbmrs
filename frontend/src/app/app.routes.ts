import { Routes } from '@angular/router';
import { authGuard } from './core/guards/auth.guard';
import { roleGuard } from './core/guards/role.guard';

export const routes: Routes = [
  // Raiz: redireciona para o dashboard (authGuard vai tratar nao-autenticados)
  {
    path: '',
    redirectTo: 'app/dashboard',
    pathMatch: 'full'
  },

  // Pagina de login (publica)
  {
    path: 'login',
    loadComponent: () =>
      import('./pages/login/login.component').then(m => m.LoginComponent)
  },

  // Area autenticada: shell com sidebar + toolbar
  {
    path: 'app',
    loadComponent: () =>
      import('./layout/shell/shell.component').then(m => m.ShellComponent),
    canActivate: [authGuard],
    children: [
      {
        path: '',
        redirectTo: 'dashboard',
        pathMatch: 'full'
      },
      {
        path: 'dashboard',
        loadComponent: () =>
          import('./pages/dashboard/dashboard.component').then(m => m.DashboardComponent)
      },

      // ── Sprint F2: Modulo de Licenciamentos ─────────────────────────────────
      // Rota pai sem componente proprio — filhos renderizam no outlet do shell.
      // canActivate no pai protege tanto a lista (/licenciamentos) quanto o
      // detalhe (/licenciamentos/:id) com uma unica declaracao de roles.
      {
        path: 'licenciamentos',
        canActivate: [roleGuard],
        data: { roles: ['CIDADAO', 'ANALISTA', 'INSPETOR', 'ADMIN', 'CHEFE_SSEG_BBM'] },
        children: [
          {
            path: '',
            loadComponent: () =>
              import('./pages/licenciamentos/licenciamentos.component')
                .then(m => m.LicenciamentosComponent)
          },
          // IMPORTANTE: rota 'novo' declarada ANTES de ':id' para que o
          // segmento literal "novo" nao seja interpretado como parametro de rota.
          {
            path: 'novo',
            canActivate: [roleGuard],
            data: { roles: ['CIDADAO', 'ADMIN'] },
            loadComponent: () =>
              import('./pages/licenciamentos/licenciamento-novo/licenciamento-novo.component')
                .then(m => m.LicenciamentoNovoComponent)
          },
          {
            path: ':id',
            loadComponent: () =>
              import('./pages/licenciamentos/licenciamento-detalhe/licenciamento-detalhe.component')
                .then(m => m.LicenciamentoDetalheComponent)
          }
        ]
      },

      // ── Sprint F4: Analise Tecnica (ANALISTA / CHEFE_SSEG_BBM) ──────────────
      // Rota pai protege toda a area de analise com uma unica declaracao de roles.
      // /app/analise      -> fila de processos pendentes (AnaliseFilaComponent)
      // /app/analise/:id  -> tela de analise de um processo especifico
      {
        path: 'analise',
        canActivate: [roleGuard],
        data: { roles: ['ANALISTA', 'CHEFE_SSEG_BBM'] },
        children: [
          {
            path: '',
            loadComponent: () =>
              import('./pages/analise/analise-fila/analise-fila.component')
                .then(m => m.AnaliseFilaComponent)
          },
          {
            path: ':id',
            loadComponent: () =>
              import('./pages/analise/licenciamento-analise/licenciamento-analise.component')
                .then(m => m.LicenciamentoAnaliseComponent)
          }
        ]
      },

      // ── Sprint F5: Vistoria Presencial (INSPETOR / CHEFE_SSEG_BBM) ──────────
      // Rota pai sem componente proprio -- filhos renderizam no outlet do shell.
      // /app/vistorias      -> fila de processos de vistoria (VistoriaFilaComponent)
      // /app/vistorias/:id  -> tela de vistoria de um processo especifico
      {
        path: 'vistorias',
        canActivate: [roleGuard],
        data: { roles: ['INSPETOR', 'CHEFE_SSEG_BBM'] },
        children: [
          {
            path: '',
            loadComponent: () =>
              import('./pages/vistoria/vistoria-fila/vistoria-fila.component')
                .then(m => m.VistoriaFilaComponent)
          },
          {
            path: ':id',
            loadComponent: () =>
              import('./pages/vistoria/vistoria-detalhe/vistoria-detalhe.component')
                .then(m => m.VistoriaDetalheComponent)
          }
        ]
      },
      // -- Sprint F6: Emissao de APPCI (ADMIN / CHEFE_SSEG_BBM) ───────────────
      // Rota pai sem componente proprio -- filhos renderizam no outlet do shell.
      // /app/appci      -> fila de processos PRPCI_EMITIDO (AppciFilaComponent)
      // /app/appci/:id  -> tela de emissao de APPCI de um processo especifico
      {
        path: 'appci',
        canActivate: [roleGuard],
        data: { roles: ['ADMIN', 'CHEFE_SSEG_BBM'] },
        children: [
          {
            path: '',
            loadComponent: () =>
              import('./pages/appci/appci-fila/appci-fila.component')
                .then(m => m.AppciFilaComponent)
          },
          {
            path: ':id',
            loadComponent: () =>
              import('./pages/appci/appci-detalhe/appci-detalhe.component')
                .then(m => m.AppciDetalheComponent)
          }
        ]
      },
      // -- Sprint F7: Recurso CIA/CIV (ANALISTA / ADMIN / CHEFE_SSEG_BBM) ─────
      // Rota pai sem componente proprio -- filhos renderizam no outlet do shell.
      // /app/recursos      -> fila de recursos pendentes (RecursoFilaComponent)
      // /app/recursos/:id  -> tela de analise/votacao/decisao do recurso
      {
        path: 'recursos',
        canActivate: [roleGuard],
        data: { roles: ['ANALISTA', 'ADMIN', 'CHEFE_SSEG_BBM'] },
        children: [
          {
            path: '',
            loadComponent: () =>
              import('./pages/recurso/recurso-fila/recurso-fila.component')
                .then(m => m.RecursoFilaComponent)
          },
          {
            path: ':id',
            loadComponent: () =>
              import('./pages/recurso/recurso-detalhe/recurso-detalhe.component')
                .then(m => m.RecursoDetalheComponent)
          }
        ]
      },

      // -- Sprint F8: Troca de Envolvidos (ADMIN / CHEFE_SSEG_BBM) ─────────────
      // Rota pai sem componente proprio -- filhos renderizam no outlet do shell.
      // /app/trocas      -> fila de solicitacoes pendentes (TrocaFilaComponent)
      // /app/trocas/:id  -> tela de analise da solicitacao (TrocaDetalheComponent)
      {
        path: 'trocas',
        canActivate: [roleGuard],
        data: { roles: ['ADMIN', 'CHEFE_SSEG_BBM'] },
        children: [
          {
            path: '',
            loadComponent: () =>
              import('./pages/troca-envolvidos/troca-fila/troca-fila.component')
                .then(m => m.TrocaFilaComponent)
          },
          {
            path: ':id',
            loadComponent: () =>
              import('./pages/troca-envolvidos/troca-detalhe/troca-detalhe.component')
                .then(m => m.TrocaDetalheComponent)
          }
        ]
      },

      // Gestao de usuarios (ADMIN) -- placeholder ate Sprint futura
      {
        path: 'usuarios',
        canActivate: [roleGuard],
        data: { roles: ['ADMIN'] },
        loadComponent: () =>
          import('./pages/not-found/not-found.component').then(m => m.NotFoundComponent)
      },
      // -- Sprint F9: Relatorios (ADMIN / CHEFE_SSEG_BBM) ─────────────────────────
      // Rota pai sem componente proprio -- filhos renderizam no outlet do shell.
      // /app/relatorios                  -> menu de relatorios (RelatoriosMenuComponent)
      // /app/relatorios/licenciamentos   -> relatorio de licenciamentos por periodo
      {
        path: 'relatorios',
        canActivate: [roleGuard],
        data: { roles: ['ADMIN', 'CHEFE_SSEG_BBM'] },
        children: [
          {
            path: '',
            loadComponent: () =>
              import('./pages/relatorios/relatorios-menu/relatorios-menu.component')
                .then(m => m.RelatoriosMenuComponent)
          },
          {
            path: 'licenciamentos',
            loadComponent: () =>
              import('./pages/relatorios/relatorio-licenciamentos/relatorio-licenciamentos.component')
                .then(m => m.RelatorioLicenciamentosComponent)
          }
        ]
      }
    ]
  },

  // Pagina 404
  {
    path: '**',
    loadComponent: () =>
      import('./pages/not-found/not-found.component').then(m => m.NotFoundComponent)
  }
];

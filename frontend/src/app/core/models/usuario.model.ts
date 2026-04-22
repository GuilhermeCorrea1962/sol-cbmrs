export type TipoUsuario =
  | 'CIDADAO'
  | 'RT'
  | 'ANALISTA'
  | 'INSPETOR'
  | 'ADMIN'
  | 'CHEFE_SSEG_BBM';

export type StatusCadastro =
  | 'INCOMPLETO'
  | 'COMPLETO'
  | 'BLOQUEADO';

export interface UsuarioDTO {
  id: number;
  keycloakId: string;
  cpf: string;
  nome: string;
  email: string;
  telefone?: string;
  tipoUsuario: TipoUsuario;
  statusCadastro: StatusCadastro;
  numeroRegistro?: string;
  tipoConselho?: string;
  especialidade?: string;
  ativo: boolean;
  dataCriacao: string;
  dataAtualizacao?: string;
}

export interface UsuarioCreateDTO {
  cpf: string;
  nome: string;
  email: string;
  telefone?: string;
  tipoUsuario: TipoUsuario;
  senha: string;
  numeroRegistro?: string;
  tipoConselho?: string;
  especialidade?: string;
}

export const TIPO_USUARIO_LABEL: Record<TipoUsuario, string> = {
  CIDADAO:       'Cidadão',
  RT:            'Resp. Técnico',
  ANALISTA:      'Analista',
  INSPETOR:      'Inspetor',
  ADMIN:         'Administrador',
  CHEFE_SSEG_BBM: 'Chefe SSEG/BBM',
};

export const TIPO_USUARIO_COLOR: Record<TipoUsuario, string> = {
  CIDADAO:       '#3498db',
  RT:            '#27ae60',
  ANALISTA:      '#8e44ad',
  INSPETOR:      '#e67e22',
  ADMIN:         '#cc0000',
  CHEFE_SSEG_BBM: '#1a1a2e',
};

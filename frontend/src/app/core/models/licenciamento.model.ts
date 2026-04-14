export type TipoLicenciamento = 'PPCI' | 'PSPCIM';

export type StatusLicenciamento =
  // Fluxo principal (P03–P08)
  | 'RASCUNHO'
  | 'ANALISE_PENDENTE'
  | 'EM_ANALISE'
  | 'CIA_EMITIDO'
  | 'CIA_CIENCIA'
  | 'DEFERIDO'
  | 'INDEFERIDO'
  | 'VISTORIA_PENDENTE'
  | 'EM_VISTORIA'
  | 'CIV_EMITIDO'
  | 'CIV_CIENCIA'
  | 'PRPCI_EMITIDO'
  | 'APPCI_EMITIDO'
  | 'ALVARA_VENCIDO'
  // Renovacao (P14)
  | 'AGUARDANDO_ACEITE_RENOVACAO'
  | 'AGUARDANDO_PAGAMENTO_RENOVACAO'
  | 'AGUARDANDO_DISTRIBUICAO_RENOV'
  | 'EM_VISTORIA_RENOVACAO'
  // Recurso (P10)
  | 'RECURSO_SUBMETIDO'
  | 'RECURSO_EM_ANALISE'
  | 'RECURSO_DEFERIDO'
  | 'RECURSO_INDEFERIDO'
  // Situacoes especiais
  | 'SUSPENSO'
  | 'EXTINTO'
  | 'RENOVADO';

export interface EnderecoDTO {
  logradouro: string;
  numero: string;
  complemento?: string;
  bairro: string;
  municipio: string;
  uf: string;
  cep: string;
}

export interface LicenciamentoDTO {
  id: number;
  numeroPpci: string | null;
  tipo: TipoLicenciamento;
  status: StatusLicenciamento;
  areaConstruida: number | null;
  alturaMaxima: number | null;
  numPavimentos: number | null;
  tipoOcupacao: string | null;
  usoPredominante: string | null;
  dtValidadeAppci: string | null;
  dtVencimentoPrpci: string | null;
  justificativaRecurso?: string | null;
  decisaoRecurso?: string | null;
  trocaPendente?: boolean;
  justificativaTroca?: string | null;
  endereco: EnderecoDTO;
  dataCriacao: string;
  dataAtualizacao: string;
}

export interface PageResponse<T> {
  content: T[];
  totalElements: number;
  totalPages: number;
  size: number;
  number: number;
}

export const STATUS_LABEL: Record<StatusLicenciamento, string> = {
  RASCUNHO:                       'Rascunho',
  ANALISE_PENDENTE:               'Analise Pendente',
  EM_ANALISE:                     'Em Analise',
  CIA_EMITIDO:                    'CIA Emitido',
  CIA_CIENCIA:                    'CIA - Ciencia RT',
  DEFERIDO:                       'Deferido',
  INDEFERIDO:                     'Indeferido',
  VISTORIA_PENDENTE:              'Vistoria Pendente',
  EM_VISTORIA:                    'Em Vistoria',
  CIV_EMITIDO:                    'CIV Emitido',
  CIV_CIENCIA:                    'CIV - Ciencia RT',
  PRPCI_EMITIDO:                  'PrPCI Emitido',
  APPCI_EMITIDO:                  'APPCI Emitido',
  ALVARA_VENCIDO:                 'Alvara Vencido',
  AGUARDANDO_ACEITE_RENOVACAO:    'Ag. Aceite Renovacao',
  AGUARDANDO_PAGAMENTO_RENOVACAO: 'Ag. Pagamento Renovacao',
  AGUARDANDO_DISTRIBUICAO_RENOV:  'Ag. Distribuicao Renov.',
  EM_VISTORIA_RENOVACAO:          'Em Vistoria (Renovacao)',
  RECURSO_SUBMETIDO:              'Recurso Submetido',
  RECURSO_EM_ANALISE:             'Recurso em Analise',
  RECURSO_DEFERIDO:               'Recurso Deferido',
  RECURSO_INDEFERIDO:             'Recurso Indeferido',
  SUSPENSO:                       'Suspenso',
  EXTINTO:                        'Extinto',
  RENOVADO:                       'Renovado'
};

export const STATUS_COLOR: Record<StatusLicenciamento, string> = {
  RASCUNHO:                       '#9e9e9e',
  ANALISE_PENDENTE:               '#f39c12',
  EM_ANALISE:                     '#3498db',
  CIA_EMITIDO:                    '#e67e22',
  CIA_CIENCIA:                    '#f39c12',
  DEFERIDO:                       '#27ae60',
  INDEFERIDO:                     '#cc0000',
  VISTORIA_PENDENTE:              '#f39c12',
  EM_VISTORIA:                    '#3498db',
  CIV_EMITIDO:                    '#e67e22',
  CIV_CIENCIA:                    '#f39c12',
  PRPCI_EMITIDO:                  '#2980b9',
  APPCI_EMITIDO:                  '#27ae60',
  ALVARA_VENCIDO:                 '#c0392b',
  AGUARDANDO_ACEITE_RENOVACAO:    '#f39c12',
  AGUARDANDO_PAGAMENTO_RENOVACAO: '#f39c12',
  AGUARDANDO_DISTRIBUICAO_RENOV:  '#f39c12',
  EM_VISTORIA_RENOVACAO:          '#3498db',
  RECURSO_SUBMETIDO:              '#1abc9c',
  RECURSO_EM_ANALISE:             '#16a085',
  RECURSO_DEFERIDO:               '#27ae60',
  RECURSO_INDEFERIDO:             '#e74c3c',
  SUSPENSO:                       '#8e44ad',
  EXTINTO:                        '#607d8b',
  RENOVADO:                       '#27ae60'
};

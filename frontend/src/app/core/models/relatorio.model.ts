// Sprint F9 -- Relatorios (P-REL)
// DTOs alinhados com os endpoints GET /api/relatorios/*
// Roles: ADMIN, CHEFE_SSEG_BBM

/**
 * Filtros para o relatorio de licenciamentos.
 * Todos os campos sao opcionais; omitir equivale a "sem restricao" no backend.
 */
export interface RelatorioLicenciamentosRequest {
  /** Data de inicio do periodo (formato yyyy-MM-dd). */
  dataInicio?: string;
  /** Data de fim do periodo (formato yyyy-MM-dd). */
  dataFim?: string;
  /** Valor do enum StatusLicenciamento. Omitir para incluir todos os status. */
  status?: string;
  /** Filtro de municipio — comparacao ILIKE no backend. */
  municipio?: string;
  /** Tipo do licenciamento: 'PPCI' | 'PSPCIM'. Omitir para incluir ambos. */
  tipo?: string;
}

/**
 * Item retornado pelo endpoint GET /api/relatorios/licenciamentos.
 * Subconjunto do LicenciamentoDTO, sem dados sensiveis de pessoa fisica.
 */
export interface RelatorioLicenciamentosItem {
  id: number;
  numeroPpci: string | null;
  tipo: string;
  status: string;
  municipio: string;
  areaConstruida: number | null;
  dataCriacao: string;      // ISO-8601
  dataAtualizacao: string;  // ISO-8601
  nomeRT: string | null;
}

/**
 * Item de resumo por status retornado pelo endpoint GET /api/relatorios/resumo-status.
 */
export interface RelatorioResumoStatusItem {
  status: string;
  label: string;
  quantidade: number;
  percentual: number;
}

/**
 * Resposta do endpoint GET /api/relatorios/resumo-status.
 * Agrega todos os licenciamentos agrupados por status.
 */
export interface RelatorioResumoStatusResponse {
  totalGeral: number;
  itens: RelatorioResumoStatusItem[];
  dataGeracao: string;  // ISO-8601
}

import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { LicenciamentoDTO, PageResponse } from '../models/licenciamento.model';
import { LicenciamentoCreateDTO } from '../models/licenciamento-create.model';
import {
  CiaCreateDTO,
  DeferimentoCreateDTO,
  IndeferimentoCreateDTO
} from '../models/analise.model';
import {
  CivCreateDTO,
  AprovacaoVistoriaCreateDTO
} from '../models/vistoria.model';
import { AppciEmitirDTO } from '../models/appci.model';
import {
  RecursoSubmeterDTO,
  RecursoRecusarDTO,
  RecursoVotoDTO,
  RecursoDecisaoDTO
} from '../models/recurso.model';
import {
  TrocaSolicitarDTO,
  TrocaAceitarDTO,
  TrocaRejeitarDTO
} from '../models/troca-envolvidos.model';
import { environment } from '../../../environments/environment';

@Injectable({ providedIn: 'root' })
export class LicenciamentoService {

  private readonly http   = inject(HttpClient);
  private readonly apiUrl = `${environment.apiUrl}/licenciamentos`;

  // ---------------------------------------------------------------------------
  // Sprint F2 — Leitura
  // ---------------------------------------------------------------------------

  /**
   * Retorna os licenciamentos do usuario autenticado (CIDADAO / RT).
   * Endpoint: GET /api/licenciamentos/meus?page=0&size=10&sort=id,desc
   */
  getMeus(page = 0, size = 10): Observable<PageResponse<LicenciamentoDTO>> {
    const params = new HttpParams()
      .set('page', page)
      .set('size', size)
      .set('sort', 'id,desc');
    return this.http.get<PageResponse<LicenciamentoDTO>>(`${this.apiUrl}/meus`, { params });
  }

  /**
   * Retorna os detalhes de um licenciamento pelo ID.
   * Endpoint: GET /api/licenciamentos/{id}
   */
  getById(id: number): Observable<LicenciamentoDTO> {
    return this.http.get<LicenciamentoDTO>(`${this.apiUrl}/${id}`);
  }

  // ---------------------------------------------------------------------------
  // Sprint F3 — Criacao e Submissao
  // ---------------------------------------------------------------------------

  /**
   * Cria um novo licenciamento em status RASCUNHO.
   * Endpoint: POST /api/licenciamentos
   * Roles: CIDADAO, RT, ADMIN
   */
  criar(dto: LicenciamentoCreateDTO): Observable<LicenciamentoDTO> {
    return this.http.post<LicenciamentoDTO>(this.apiUrl, dto);
  }

  /**
   * Submete um licenciamento em RASCUNHO para analise (ANALISE_PENDENTE).
   * Endpoint: POST /api/licenciamentos/{id}/submeter
   * Roles: CIDADAO, RT, ADMIN
   */
  submeter(id: number): Observable<LicenciamentoDTO> {
    return this.http.post<LicenciamentoDTO>(`${this.apiUrl}/${id}/submeter`, {});
  }

  // ---------------------------------------------------------------------------
  // Sprint F4 — Analise Tecnica
  // ---------------------------------------------------------------------------

  /**
   * Retorna a fila de analise tecnica paginada, ordenada por data de entrada (FIFO).
   * Inclui processos com status ANALISE_PENDENTE e EM_ANALISE.
   * Endpoint: GET /api/licenciamentos/fila-analise?page=0&size=10&sort=dataCriacao,asc
   * Roles: ANALISTA, CHEFE_SSEG_BBM
   */
  getFilaAnalise(page = 0, size = 10): Observable<PageResponse<LicenciamentoDTO>> {
    const params = new HttpParams()
      .set('page', page)
      .set('size', size)
      .set('sort', 'dataCriacao,asc');
    return this.http.get<PageResponse<LicenciamentoDTO>>(`${this.apiUrl}/fila-analise`, { params });
  }

  /**
   * Assume o processo para analise tecnica.
   * Endpoint: POST /api/licenciamentos/{id}/iniciar-analise
   * Roles: ANALISTA, CHEFE_SSEG_BBM
   * Transicao: ANALISE_PENDENTE -> EM_ANALISE
   */
  iniciarAnalise(id: number): Observable<LicenciamentoDTO> {
    return this.http.post<LicenciamentoDTO>(`${this.apiUrl}/${id}/iniciar-analise`, {});
  }

  /**
   * Emite um CIA (Comunicado de Inconformidade na Analise).
   * Endpoint: POST /api/licenciamentos/{id}/cia
   * Roles: ANALISTA, CHEFE_SSEG_BBM
   * Transicao: EM_ANALISE -> CIA_EMITIDO
   */
  emitirCia(id: number, dto: CiaCreateDTO): Observable<LicenciamentoDTO> {
    return this.http.post<LicenciamentoDTO>(`${this.apiUrl}/${id}/cia`, dto);
  }

  /**
   * Defere a analise tecnica.
   * Endpoint: POST /api/licenciamentos/{id}/deferir
   * Roles: ANALISTA, CHEFE_SSEG_BBM
   * Transicao: EM_ANALISE -> VISTORIA_PENDENTE (PPCI) ou DEFERIDO (PSPCIM)
   */
  deferir(id: number, dto: DeferimentoCreateDTO): Observable<LicenciamentoDTO> {
    return this.http.post<LicenciamentoDTO>(`${this.apiUrl}/${id}/deferir`, dto);
  }

  /**
   * Indefere a analise tecnica.
   * Endpoint: POST /api/licenciamentos/{id}/indeferir
   * Roles: ANALISTA, CHEFE_SSEG_BBM
   * Transicao: EM_ANALISE -> INDEFERIDO
   */
  indeferir(id: number, dto: IndeferimentoCreateDTO): Observable<LicenciamentoDTO> {
    return this.http.post<LicenciamentoDTO>(`${this.apiUrl}/${id}/indeferir`, dto);
  }

  // ---------------------------------------------------------------------------
  // Sprint F5 -- Vistoria Presencial
  // ---------------------------------------------------------------------------

  /**
   * Retorna a fila de vistoria presencial paginada, ordenada por data de entrada (FIFO).
   * Inclui processos com status VISTORIA_PENDENTE, EM_VISTORIA e EM_VISTORIA_RENOVACAO.
   * Endpoint: GET /api/licenciamentos/fila-vistoria?page=0&size=10&sort=dataCriacao,asc
   * Roles: INSPETOR, CHEFE_SSEG_BBM
   */
  getFilaVistoria(page = 0, size = 10): Observable<PageResponse<LicenciamentoDTO>> {
    const params = new HttpParams()
      .set('page', page)
      .set('size', size)
      .set('sort', 'dataCriacao,asc');
    return this.http.get<PageResponse<LicenciamentoDTO>>(`${this.apiUrl}/fila-vistoria`, { params });
  }

  /**
   * Assume o processo para vistoria presencial.
   * Endpoint: POST /api/licenciamentos/{id}/iniciar-vistoria
   * Roles: INSPETOR, CHEFE_SSEG_BBM
   * Transicao: VISTORIA_PENDENTE -> EM_VISTORIA
   */
  iniciarVistoria(id: number): Observable<LicenciamentoDTO> {
    return this.http.post<LicenciamentoDTO>(`${this.apiUrl}/${id}/iniciar-vistoria`, {});
  }

  /**
   * Emite um CIV (Comunicado de Inconformidade na Vistoria).
   * Endpoint: POST /api/licenciamentos/{id}/civ
   * Roles: INSPETOR, CHEFE_SSEG_BBM
   * Transicao: EM_VISTORIA -> CIV_EMITIDO
   */
  emitirCiv(id: number, dto: CivCreateDTO): Observable<LicenciamentoDTO> {
    return this.http.post<LicenciamentoDTO>(`${this.apiUrl}/${id}/civ`, dto);
  }

  /**
   * Aprova a vistoria presencial e emite o PrPCI.
   * Endpoint: POST /api/licenciamentos/{id}/aprovar-vistoria
   * Roles: INSPETOR, CHEFE_SSEG_BBM
   * Transicao: EM_VISTORIA -> PRPCI_EMITIDO
   */
  aprovarVistoria(id: number, dto: AprovacaoVistoriaCreateDTO): Observable<LicenciamentoDTO> {
    return this.http.post<LicenciamentoDTO>(`${this.apiUrl}/${id}/aprovar-vistoria`, dto);
  }

  // ---------------------------------------------------------------------------
  // Sprint F6 -- Emissao de APPCI (P08)
  // ---------------------------------------------------------------------------

  /**
   * Retorna a fila de emissao de APPCI paginada, ordenada por data de entrada (FIFO).
   * Inclui processos com status PRPCI_EMITIDO aguardando emissao do alvara.
   * Endpoint: GET /api/licenciamentos/fila-appci?page=0&size=10&sort=dataCriacao,asc
   * Roles: ADMIN, CHEFE_SSEG_BBM
   */
  getFilaAppci(page = 0, size = 10): Observable<PageResponse<LicenciamentoDTO>> {
    const params = new HttpParams()
      .set('page', page)
      .set('size', size)
      .set('sort', 'dataCriacao,asc');
    return this.http.get<PageResponse<LicenciamentoDTO>>(`${this.apiUrl}/fila-appci`, { params });
  }

  /**
   * Emite o APPCI (Alvara de Prevencao e Protecao Contra Incendio).
   * Endpoint: POST /api/licenciamentos/{id}/emitir-appci
   * Roles: ADMIN, CHEFE_SSEG_BBM
   * Transicao: PRPCI_EMITIDO -> APPCI_EMITIDO
   * Obs: a validade do APPCI (2 ou 5 anos) e calculada pelo backend
   *      com base no tipo de ocupacao, conforme RTCBMRS N.01/2024.
   */
  emitirAppci(id: number, dto: AppciEmitirDTO): Observable<LicenciamentoDTO> {
    return this.http.post<LicenciamentoDTO>(`${this.apiUrl}/${id}/emitir-appci`, dto);
  }

  // ---------------------------------------------------------------------------
  // Sprint F7 -- Recurso CIA/CIV (P10)
  // ---------------------------------------------------------------------------

  /**
   * Retorna a fila de recursos paginada, ordenada por data de atualizacao (FIFO).
   * Inclui processos com status RECURSO_SUBMETIDO e RECURSO_EM_ANALISE.
   * Endpoint: GET /api/licenciamentos/fila-recurso?page=0&size=10&sort=dataAtualizacao,asc
   * Roles: ANALISTA, ADMIN, CHEFE_SSEG_BBM
   */
  getFilaRecurso(page = 0, size = 10): Observable<PageResponse<LicenciamentoDTO>> {
    const params = new HttpParams()
      .set('page', page)
      .set('size', size)
      .set('sort', 'dataAtualizacao,asc');
    return this.http.get<PageResponse<LicenciamentoDTO>>(`${this.apiUrl}/fila-recurso`, { params });
  }

  /**
   * Submete um recurso contra CIA ou CIV emitido.
   * Endpoint: POST /api/licenciamentos/{id}/submeter-recurso
   * Roles: RT do licenciamento (autenticado)
   * Transicao: CIA_EMITIDO | CIV_EMITIDO -> RECURSO_SUBMETIDO
   * RN: Enquanto houver recurso ativo, o PPCI fica bloqueado para nova analise (RN-089).
   */
  submeterRecurso(id: number, dto: RecursoSubmeterDTO): Observable<LicenciamentoDTO> {
    return this.http.post<LicenciamentoDTO>(`${this.apiUrl}/${id}/submeter-recurso`, dto);
  }

  /**
   * Aceita o recurso para analise pela comissao.
   * Endpoint: POST /api/licenciamentos/{id}/aceitar-recurso
   * Roles: ADMIN, CHEFE_SSEG_BBM
   * Transicao: RECURSO_SUBMETIDO -> RECURSO_EM_ANALISE
   */
  aceitarRecurso(id: number): Observable<LicenciamentoDTO> {
    return this.http.post<LicenciamentoDTO>(`${this.apiUrl}/${id}/aceitar-recurso`, {});
  }

  /**
   * Recusa o recurso na triagem (sem encaminhar para comissao).
   * Endpoint: POST /api/licenciamentos/{id}/recusar-recurso
   * Roles: ADMIN, CHEFE_SSEG_BBM
   * Transicao: RECURSO_SUBMETIDO -> CIA_EMITIDO | CIV_EMITIDO (retorna ao estado anterior)
   */
  recusarRecurso(id: number, dto: RecursoRecusarDTO): Observable<LicenciamentoDTO> {
    return this.http.post<LicenciamentoDTO>(`${this.apiUrl}/${id}/recusar-recurso`, dto);
  }

  /**
   * Registra o voto de um membro da comissao sobre o recurso.
   * Endpoint: POST /api/licenciamentos/{id}/votar-recurso
   * Roles: ANALISTA, CHEFE_SSEG_BBM
   * Transicao: incrementa contagem de votos em RECURSO_EM_ANALISE
   * RN: exige unanimidade dos membros presentes; backend controla quorum.
   */
  votarRecurso(id: number, dto: RecursoVotoDTO): Observable<LicenciamentoDTO> {
    return this.http.post<LicenciamentoDTO>(`${this.apiUrl}/${id}/votar-recurso`, dto);
  }

  /**
   * Registra a decisao final do recurso pelo ADMIN apos votacao da comissao.
   * Endpoint: POST /api/licenciamentos/{id}/decidir-recurso
   * Roles: ADMIN, CHEFE_SSEG_BBM
   * Transicao: RECURSO_EM_ANALISE -> RECURSO_DEFERIDO | RECURSO_INDEFERIDO
   * Se DEFERIDO: licenciamento retorna ao fluxo normal (EM_ANALISE ou EM_VISTORIA).
   * Se INDEFERIDO: CIA/CIV original e mantido; RT pode iniciar novo processo.
   */
  decidirRecurso(id: number, dto: RecursoDecisaoDTO): Observable<LicenciamentoDTO> {
    return this.http.post<LicenciamentoDTO>(`${this.apiUrl}/${id}/decidir-recurso`, dto);
  }

  // ---------------------------------------------------------------------------
  // Sprint F8 -- Troca de Envolvidos (P09)
  // ---------------------------------------------------------------------------

  /**
   * Retorna a fila de licenciamentos com solicitacao de troca pendente.
   * Endpoint: GET /api/licenciamentos/fila-troca?page=0&size=10&sort=dataAtualizacao,asc
   * Roles: ADMIN, CHEFE_SSEG_BBM
   * Filtra: LicenciamentoDTO.trocaPendente == true
   */
  getFilaTrocaPendente(page = 0, size = 10): Observable<PageResponse<LicenciamentoDTO>> {
    const params = new HttpParams()
      .set('page', page)
      .set('size', size)
      .set('sort', 'dataAtualizacao,asc');
    return this.http.get<PageResponse<LicenciamentoDTO>>(`${this.apiUrl}/fila-troca`, { params });
  }

  /**
   * RT atual solicita sua propria saida do licenciamento.
   * Endpoint: POST /api/licenciamentos/{id}/solicitar-troca
   * Roles: RT do licenciamento (autenticado)
   * Efeito: LicenciamentoDTO.trocaPendente = true
   * RN: bloqueado se recurso ativo (RN-089) ou status terminal.
   */
  solicitarTroca(id: number, dto: TrocaSolicitarDTO): Observable<LicenciamentoDTO> {
    return this.http.post<LicenciamentoDTO>(`${this.apiUrl}/${id}/solicitar-troca`, dto);
  }

  /**
   * Admin aceita a solicitacao de troca de RT.
   * Endpoint: POST /api/licenciamentos/{id}/aceitar-troca
   * Roles: ADMIN, CHEFE_SSEG_BBM
   * Efeito: backend notifica novo RT para associacao; trocaPendente permanece true
   *         ate o novo RT confirmar (fora do escopo desta sprint).
   */
  aceitarTroca(id: number, dto: TrocaAceitarDTO): Observable<LicenciamentoDTO> {
    return this.http.post<LicenciamentoDTO>(`${this.apiUrl}/${id}/aceitar-troca`, dto);
  }

  /**
   * Admin rejeita a solicitacao de troca de RT.
   * Endpoint: POST /api/licenciamentos/{id}/rejeitar-troca
   * Roles: ADMIN, CHEFE_SSEG_BBM
   * Efeito: LicenciamentoDTO.trocaPendente = false; RT permanece no licenciamento.
   */
  rejeitarTroca(id: number, dto: TrocaRejeitarDTO): Observable<LicenciamentoDTO> {
    return this.http.post<LicenciamentoDTO>(`${this.apiUrl}/${id}/rejeitar-troca`, dto);
  }
}

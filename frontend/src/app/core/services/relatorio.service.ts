import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import {
  RelatorioLicenciamentosRequest,
  RelatorioLicenciamentosItem,
  RelatorioResumoStatusResponse
} from '../models/relatorio.model';
import { PageResponse } from '../models/licenciamento.model';
import { environment } from '../../../environments/environment';

// Sprint F9 -- Relatorios (P-REL)
// Endpoints: GET /api/relatorios/*
// Roles: ADMIN, CHEFE_SSEG_BBM
@Injectable({ providedIn: 'root' })
export class RelatorioService {

  private readonly http   = inject(HttpClient);
  private readonly relUrl = `${environment.apiUrl}/relatorios`;

  // ---------------------------------------------------------------------------
  // Sprint F9 -- Relatorio de Licenciamentos
  // ---------------------------------------------------------------------------

  /**
   * Retorna lista paginada de licenciamentos com os filtros aplicados.
   * Endpoint: GET /api/relatorios/licenciamentos
   * Parametros de query: dataInicio, dataFim, status, municipio, tipo, page, size, sort
   */
  getLicenciamentos(
    filtro: RelatorioLicenciamentosRequest,
    page = 0,
    size = 50
  ): Observable<PageResponse<RelatorioLicenciamentosItem>> {
    let params = new HttpParams()
      .set('page', page)
      .set('size', size)
      .set('sort', 'dataCriacao,desc');
    if (filtro.dataInicio) { params = params.set('dataInicio', filtro.dataInicio); }
    if (filtro.dataFim)    { params = params.set('dataFim',    filtro.dataFim);    }
    if (filtro.status)     { params = params.set('status',     filtro.status);     }
    if (filtro.municipio)  { params = params.set('municipio',  filtro.municipio);  }
    if (filtro.tipo)       { params = params.set('tipo',       filtro.tipo);       }
    return this.http.get<PageResponse<RelatorioLicenciamentosItem>>(
      `${this.relUrl}/licenciamentos`, { params }
    );
  }

  /**
   * Retorna o resumo agregado de licenciamentos agrupados por status.
   * Endpoint: GET /api/relatorios/resumo-status
   * Usado pelo painel de resumo na pagina inicial do modulo de relatorios.
   */
  getResumoStatus(): Observable<RelatorioResumoStatusResponse> {
    return this.http.get<RelatorioResumoStatusResponse>(`${this.relUrl}/resumo-status`);
  }

  /**
   * Exporta o relatorio de licenciamentos filtrado como arquivo CSV.
   * Endpoint: GET /api/relatorios/licenciamentos/csv
   * Retorna Blob; o componente e responsavel por acionar o download no browser.
   */
  exportarCSV(filtro: RelatorioLicenciamentosRequest): Observable<Blob> {
    let params = new HttpParams();
    if (filtro.dataInicio) { params = params.set('dataInicio', filtro.dataInicio); }
    if (filtro.dataFim)    { params = params.set('dataFim',    filtro.dataFim);    }
    if (filtro.status)     { params = params.set('status',     filtro.status);     }
    if (filtro.municipio)  { params = params.set('municipio',  filtro.municipio);  }
    if (filtro.tipo)       { params = params.set('tipo',       filtro.tipo);       }
    return this.http.get(`${this.relUrl}/licenciamentos/csv`, {
      params,
      responseType: 'blob'
    });
  }
}

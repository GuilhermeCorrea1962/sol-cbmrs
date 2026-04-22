import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../../environments/environment';
import { UsuarioDTO, UsuarioCreateDTO } from '../models/usuario.model';

@Injectable({ providedIn: 'root' })
export class UsuarioService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiUrl}/usuarios`;

  listar(): Observable<UsuarioDTO[]> {
    return this.http.get<UsuarioDTO[]>(this.base);
  }

  criar(dto: UsuarioCreateDTO): Observable<UsuarioDTO> {
    return this.http.post<UsuarioDTO>(this.base, dto);
  }

  atualizar(id: number, dto: Partial<UsuarioDTO>): Observable<UsuarioDTO> {
    return this.http.put<UsuarioDTO>(`${this.base}/${id}`, dto);
  }

  desativar(id: number): Observable<void> {
    return this.http.delete<void>(`${this.base}/${id}`);
  }
}

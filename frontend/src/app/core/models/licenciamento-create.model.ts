import { TipoLicenciamento } from './licenciamento.model';

/**
 * Payload enviado ao endpoint POST /api/licenciamentos.
 * Espelha o Java record LicenciamentoCreateDTO.
 * Campos responsavelTecnicoId, responsavelUsoId e licenciamentoPaiId
 * sao opcionais e reservados para sprints futuras.
 */
export interface LicenciamentoCreateDTO {
  tipo: TipoLicenciamento;
  areaConstruida: number;
  alturaMaxima: number;
  numPavimentos: number;
  tipoOcupacao?: string;
  usoPredominante?: string;
  endereco: EnderecoCreateDTO;
  responsavelTecnicoId?: number;
  responsavelUsoId?: number;
  licenciamentoPaiId?: number;
}

/**
 * Subconjunto do Java record EnderecoDTO usado na criacao.
 * cep: 8 digitos numericos sem hifen (ex: "90050170").
 * uf:  2 letras maiusculas (ex: "RS").
 */
export interface EnderecoCreateDTO {
  cep: string;
  logradouro: string;
  numero?: string;
  complemento?: string;
  bairro: string;
  municipio: string;
  uf: string;
}

/** Lista dos estados brasileiros para o campo UF no formulario. */
export const UF_OPTIONS: { sigla: string; nome: string }[] = [
  { sigla: 'AC', nome: 'Acre' },
  { sigla: 'AL', nome: 'Alagoas' },
  { sigla: 'AP', nome: 'Amapa' },
  { sigla: 'AM', nome: 'Amazonas' },
  { sigla: 'BA', nome: 'Bahia' },
  { sigla: 'CE', nome: 'Ceara' },
  { sigla: 'DF', nome: 'Distrito Federal' },
  { sigla: 'ES', nome: 'Espirito Santo' },
  { sigla: 'GO', nome: 'Goias' },
  { sigla: 'MA', nome: 'Maranhao' },
  { sigla: 'MT', nome: 'Mato Grosso' },
  { sigla: 'MS', nome: 'Mato Grosso do Sul' },
  { sigla: 'MG', nome: 'Minas Gerais' },
  { sigla: 'PA', nome: 'Para' },
  { sigla: 'PB', nome: 'Paraiba' },
  { sigla: 'PR', nome: 'Parana' },
  { sigla: 'PE', nome: 'Pernambuco' },
  { sigla: 'PI', nome: 'Piaui' },
  { sigla: 'RJ', nome: 'Rio de Janeiro' },
  { sigla: 'RN', nome: 'Rio Grande do Norte' },
  { sigla: 'RS', nome: 'Rio Grande do Sul' },
  { sigla: 'RO', nome: 'Rondonia' },
  { sigla: 'RR', nome: 'Roraima' },
  { sigla: 'SC', nome: 'Santa Catarina' },
  { sigla: 'SP', nome: 'Sao Paulo' },
  { sigla: 'SE', nome: 'Sergipe' },
  { sigla: 'TO', nome: 'Tocantins' }
];

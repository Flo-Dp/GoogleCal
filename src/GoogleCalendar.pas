unit GoogleCalendar;

{ Accès à l'API Google Calendar v3 avec un jeton fourni par TGoogleAuth.
  Opérations couvertes :
    - ListerCalendriers   : liste les calendriers accessibles (calendarList.list)
    - TrouverCalendrier   : retrouve un calendrier par son nom ou son ID
    - SupprimerCalendrier : supprime définitivement un calendrier (calendars.delete)
    - RetirerDeLaListe    : retire un calendrier partagé de sa propre liste
                            (calendarList.delete, le propriétaire le conserve) }

interface

uses
  System.SysUtils, System.StrUtils, System.JSON, System.NetEncoding,
  REST.Types, REST.Client, GoogleAuth;

type
  TInfoCalendrier = record
    Id: string;
    Nom: string;
    Fuseau: string;
    EstPrincipal: Boolean;
    PeutSupprimer: Boolean;
  end;

  TGoogleCalendrier = class
  strict private
    FAuth: TGoogleAuth;
    FDernierStatut: Integer;
    FDerniereErreur: string;
    function RequeteUneFois(const AMethode: TRESTRequestMethod;
      const ARessource: string): TJSONValue;
    function Requete(const AMethode: TRESTRequestMethod;
      const ARessource: string): TJSONValue;
    function MessageErreurHTTP(const AReponse: string;
      const AStatut: Integer): string;
  public
    constructor Create(AAuth: TGoogleAuth);

    function ListerCalendriers: TArray<TInfoCalendrier>;
    function TrouverCalendrier(const ANomOuId: string;
      out ACalendrier: TInfoCalendrier): Boolean;
    function SupprimerCalendrier(const AId: string): Boolean;
    function RetirerDeLaListe(const AId: string): Boolean;

    property DernierStatut: Integer read FDernierStatut;
    property DerniereErreur: string read FDerniereErreur;
  end;

const
  BASE_URL_API_AGENDA = 'https://www.googleapis.com/calendar/v3/';

implementation

{ TGoogleCalendrier }

constructor TGoogleCalendrier.Create(AAuth: TGoogleAuth);
begin
  inherited Create;
  FAuth := AAuth;
end;

function TGoogleCalendrier.MessageErreurHTTP(const AReponse: string;
  const AStatut: Integer): string;
var
  J: TJSONValue;
  Msg: string;
begin
  Msg := '';
  J := TJSONObject.ParseJSONValue(AReponse);
  if J <> nil then
    try
      J.TryGetValue<string>('error.message', Msg);
    finally
      J.Free;
    end;

  case AStatut of
    400: Result := 'Opération refusée : le calendrier principal ne peut pas être supprimé.';
    401: Result := 'Authentification expirée : merci de vous reconnecter.';
    403: Result := 'Accès refusé : scope ou droits insuffisants pour ce calendrier.';
    404: Result := 'Calendrier introuvable ou sans droit de suppression.';
  else
    Result := 'Erreur HTTP ' + IntToStr(AStatut);
  end;
  if Msg <> '' then
    Result := Result + ' - ' + Msg;
end;

function TGoogleCalendrier.RequeteUneFois(const AMethode: TRESTRequestMethod;
  const ARessource: string): TJSONValue;
var
  Client: TRESTClient;
  Req: TRESTRequest;
  Rep: TRESTResponse;
  Token, Erreur: string;
begin
  Result := nil;
  FDerniereErreur := '';
  Token := FAuth.ObtenirToken(Erreur);
  if Token = '' then
  begin
    FDernierStatut := 0;
    FDerniereErreur := Erreur;
    Exit;
  end;

  Client := TRESTClient.Create(BASE_URL_API_AGENDA);
  try
    Rep := TRESTResponse.Create(Client);
    Req := TRESTRequest.Create(Client);
    Req.Client := Client;
    Req.Response := Rep;
    Req.Method := AMethode;
    Req.Resource := ARessource;
    Req.Accept := 'application/json';
    Req.AddParameter('Authorization', 'Bearer ' + Token,
      pkHTTPHEADER, [poDoNotEncode]);
    try
      Req.Execute;
      FDernierStatut := Rep.StatusCode;
      case FDernierStatut of
        200, 201: Result := TJSONObject.ParseJSONValue(Rep.Content);
        204: ; // succès sans contenu (DELETE)
        401:   FDerniereErreur := 'Jeton expiré.';
      else
        FDerniereErreur := MessageErreurHTTP(Rep.Content, FDernierStatut);
      end;
    except
      on E: Exception do
      begin
        FDernierStatut := 0;
        FDerniereErreur := E.Message;
      end;
    end;
  finally
    Client.Free;
  end;
end;

function TGoogleCalendrier.Requete(const AMethode: TRESTRequestMethod;
  const ARessource: string): TJSONValue;
begin
  // une tentative + un second essai après rafraîchissement du token en cas de 401
  Result := RequeteUneFois(AMethode, ARessource);
  if FDernierStatut = 401 then
  begin
    FAuth.InvaliderAccessToken;
    Result := RequeteUneFois(AMethode, ARessource);
  end;
end;

function TGoogleCalendrier.ListerCalendriers: TArray<TInfoCalendrier>;
var
  J, JItem: TJSONValue;
  Items: TJSONArray;
  PageToken: string;
  n, i: Integer;
begin
  SetLength(Result, 0);
  FDerniereErreur := '';
  PageToken := '';
  repeat
    if PageToken = '' then
      J := Requete(rmGET, 'users/me/calendarList?maxResults=250')
    else
      J := Requete(rmGET, 'users/me/calendarList?maxResults=250&pageToken=' +
        TNetEncoding.URL.Encode(PageToken));
    if J = nil then
      Exit;

    Items := J.FindValue('items') as TJSONArray;
    if Items <> nil then
    begin
      n := Length(Result);
      SetLength(Result, n + Items.Count);
      for i := 0 to Items.Count - 1 do
      begin
        JItem := Items.Items[i];
        Result[n + i].Id := JItem.GetValue<string>('id', '');
        Result[n + i].Nom := JItem.GetValue<string>('summary', '');
        Result[n + i].Fuseau := JItem.GetValue<string>('timeZone', '');
        Result[n + i].EstPrincipal := JItem.GetValue<Boolean>('primary', False);
        Result[n + i].PeutSupprimer :=
          (not JItem.GetValue<Boolean>('primary', False)) and
          SameText(JItem.GetValue<string>('accessRole', ''), 'owner');
      end;
    end;

    PageToken := J.GetValue<string>('nextPageToken', '');
    J.Free;
  until PageToken = '';
end;

function TGoogleCalendrier.TrouverCalendrier(const ANomOuId: string;
  out ACalendrier: TInfoCalendrier): Boolean;
var
  Liste: TArray<TInfoCalendrier>;
  C: TInfoCalendrier;
begin
  Result := False;
  Liste := ListerCalendriers;
  if FDerniereErreur <> '' then
    Exit;
  for C in Liste do
    if SameText(C.Id, ANomOuId) or SameText(C.Nom, ANomOuId) then
    begin
      ACalendrier := C;
      Exit(True);
    end;
  FDerniereErreur :=
    'Aucun calendrier ne correspond à « ' + ANomOuId + ' ».';
end;

function TGoogleCalendrier.SupprimerCalendrier(const AId: string): Boolean;
begin
  Requete(rmDELETE, 'calendars/' + TNetEncoding.URL.EncodePathSegment(AId));
  Result := FDerniereErreur = '';
end;

function TGoogleCalendrier.RetirerDeLaListe(const AId: string): Boolean;
begin
  Requete(rmDELETE, 'users/me/calendarList/' +
    TNetEncoding.URL.EncodePathSegment(AId));
  Result := FDerniereErreur = '';
end;

end.

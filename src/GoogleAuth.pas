unit GoogleAuth;

{ Authentification OAuth 2.0 pour les API Google (application de bureau VCL).
  Méthode recommandée par Google pour les apps installées : ouverture du
  navigateur par défaut + serveur HTTP de rebouclage local (127.0.0.1) qui
  capture le code d'autorisation, puis échange contre les tokens.

  Prérequis côté Google Cloud Console :
    - API Google Calendar activée
    - ID client OAuth de type "Application de bureau"
    - URI de redirection autorisée : http://localhost:8099/ (par défaut ici) }

interface

uses
  System.SysUtils, System.Classes, System.StrUtils, System.DateUtils,
  System.JSON, System.Net.URLClient, System.IOUtils, Winapi.Windows,
  Winapi.ShellAPI, VCL.Forms,
  REST.Types, REST.Client,
  IdContext, IdCustomHTTPServer, IdHTTPServer, IdSocketHandle;

const
  URL_AUTORISATION = 'https://accounts.google.com/o/oauth2/v2/auth';
  URL_TOKEN        = 'https://oauth2.googleapis.com/token';
  SCOPE_AGENDA     = 'https://www.googleapis.com/auth/calendar';

type
  TGoogleAuth = class
  strict private
    FClientId: string;
    FClientSecret: string;
    FRedirectURI: string;
    FPort: Word;
    FServeur: TIdHTTPServer;
    FState: string;
    FCodeRecu: string;
    FConnexionTerminee: Boolean;
    FAnnule: Boolean;
    FAccessToken: string;
    FRefreshToken: string;
    FExpiration: TDateTime;
    procedure RequeteRecue(AContext: TIdContext;
      ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    function AppelToken(const AParams: TArray<string>;
      out AErreur: string): Boolean;
    function EchangerCode(const ACode: string; out AErreur: string): Boolean;
    function RafraichirToken(out AErreur: string): Boolean;
  public
    constructor Create(const AClientId, AClientSecret: string;
      const ARedirectURI: string = 'http://localhost:8099/');
    destructor Destroy; override;

    function SeConnecter(const AScope: string; out AErreur: string): Boolean;
    function ObtenirToken(out AErreur: string): string;
    procedure InvaliderAccessToken;
    function JetonEnCacheValide: Boolean;
    procedure SauverDansFichier(const AFichier: string);
    procedure ChargerDepuisFichier(const AFichier: string);

    property RefreshToken: string read FRefreshToken write FRefreshToken;
  end;

implementation

{ TGoogleAuth }

constructor TGoogleAuth.Create(const AClientId, AClientSecret: string;
  const ARedirectURI: string);
begin
  inherited Create;
  FClientId := AClientId;
  FClientSecret := AClientSecret;
  FRedirectURI := ARedirectURI;
  FPort := TURI.Create(ARedirectURI).Port;
  FServeur := TIdHTTPServer.Create(nil);
  FServeur.OnCommandGet := RequeteRecue;
end;

destructor TGoogleAuth.Destroy;
begin
  FServeur.Active := False;
  FServeur.Free;
  inherited;
end;

procedure TGoogleAuth.RequeteRecue(AContext: TIdContext;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  Code, State: string;
begin
  Code := ARequestInfo.Params.Values['code'];
  State := ARequestInfo.Params.Values['state'];

  TThread.Synchronize(nil,
    procedure
    begin
      FConnexionTerminee := True;
      if (State = FState) and (Code <> '') then
        FCodeRecu := Code
      else
        FAnnule := True;
    end);

  AResponseInfo.ContentType := 'text/html; charset=utf-8';
  if FAnnule then
    AResponseInfo.ContentText :=
      '<html><body><h2>Connexion annulée ou échouée.</h2>Cette fenêtre peut être fermée.</body></html>'
  else
    AResponseInfo.ContentText :=
      '<html><body><h2>Connexion réussie.</h2>Vous pouvez fermer cette fenêtre et revenir à l''application.</body></html>';
end;

function TGoogleAuth.SeConnecter(const AScope: string; out AErreur: string): Boolean;
var
  Uri: TURI;
  Bind: TIdSocketHandle;
  Temps: Integer;
begin
  Result := False;
  AErreur := '';

  // 1) refresh token déjà en mémoire : on tente un rafraîchissement transparent
  if FRefreshToken <> '' then
    if RafraichirToken(AErreur) then
      Exit(True)
    else
      FRefreshToken := '';

  // 2) autorisation complète dans le navigateur par défaut
  FState := TGUID.NewGuid.ToString;
  Uri := TURI.Create(URL_AUTORISATION);
  Uri.AddParameter('client_id', FClientId);
  Uri.AddParameter('redirect_uri', FRedirectURI);
  Uri.AddParameter('response_type', 'code');
  Uri.AddParameter('scope', AScope);
  Uri.AddParameter('access_type', 'offline');
  Uri.AddParameter('prompt', 'consent');
  Uri.AddParameter('state', FState);

  FCodeRecu := '';
  FConnexionTerminee := False;
  FAnnule := False;

  FServeur.Bindings.Clear;
  Bind := FServeur.Bindings.Add;
  Bind.IP := '127.0.0.1';
  Bind.Port := FPort;
  FServeur.Active := True;
  try
    if ShellExecute(0, 'open', PChar(Uri.ToString), nil, nil,
      SW_SHOWNORMAL) <= 32 then
    begin
      AErreur := 'Impossible d''ouvrir le navigateur vers Google.';
      Exit;
    end;

    Temps := 0;
    while not FConnexionTerminee and (Temps < 120000) do
    begin
      Sleep(50);
      Inc(Temps, 50);
      Application.ProcessMessages;
    end;
  finally
    FServeur.Active := False;
  end;

  if FAnnule then
  begin
    AErreur := 'Autorisation refusée ou annulée par l''utilisateur.';
    Exit;
  end;
  if FCodeRecu = '' then
  begin
    AErreur := 'Délai dépassé : le code d''autorisation n''a pas été reçu.';
    Exit;
  end;

  Result := EchangerCode(FCodeRecu, AErreur);
end;

function TGoogleAuth.AppelToken(const AParams: TArray<string>;
  out AErreur: string): Boolean;
var
  Client: TRESTClient;
  Req: TRESTRequest;
  Rep: TRESTResponse;
  J: TJSONValue;
  i: Integer;
  RefreshToken: string;
begin
  Result := False;
  AErreur := '';
  Client := TRESTClient.Create(URL_TOKEN);
  try
    Rep := TRESTResponse.Create(Client);
    Req := TRESTRequest.Create(Client);
    Req.Client := Client;
    Req.Response := Rep;
    Req.Method := rmPOST;
    i := 0;
    while i <= High(AParams) do
    begin
      Req.AddParameter(AParams[i], AParams[i + 1], pkGETorPOST);
      Inc(i, 2);
    end;
    try
      Req.Execute;
    except
      on E: Exception do
      begin
        AErreur := 'Erreur réseau : ' + E.Message;
        Exit;
      end;
    end;

    if Rep.StatusCode <> 200 then
    begin
      if (Rep.StatusCode = 400) and (Pos('invalid_grant', Rep.Content) > 0) then
        FRefreshToken := '';
      AErreur := 'Erreur OAuth HTTP ' + IntToStr(Rep.StatusCode) +
        ' : ' + Rep.Content;
      Exit;
    end;

    J := TJSONObject.ParseJSONValue(Rep.Content);
    if J = nil then
    begin
      AErreur := 'Réponse du serveur de tokens illisible.';
      Exit;
    end;
    try
      FAccessToken := J.GetValue<string>('access_token');
      FExpiration := IncSecond(Now, J.GetValue<Integer>('expires_in', 3600) - 60);
      if J.TryGetValue<string>('refresh_token', RefreshToken) and
        (RefreshToken <> '') then
        FRefreshToken := RefreshToken;
    finally
      J.Free;
    end;
    Result := True;
  finally
    Client.Free;
  end;
end;

function TGoogleAuth.EchangerCode(const ACode: string;
  out AErreur: string): Boolean;
begin
  Result := AppelToken(['code', ACode,
                        'client_id', FClientId,
                        'client_secret', FClientSecret,
                        'redirect_uri', FRedirectURI,
                        'grant_type', 'authorization_code'], AErreur);
end;

function TGoogleAuth.RafraichirToken(out AErreur: string): Boolean;
begin
  Result := AppelToken(['refresh_token', FRefreshToken,
                        'client_id', FClientId,
                        'client_secret', FClientSecret,
                        'grant_type', 'refresh_token'], AErreur);
end;

function TGoogleAuth.ObtenirToken(out AErreur: string): string;
begin
  AErreur := '';
  if (FAccessToken = '') or (Now >= FExpiration) then
    if not RafraichirToken(AErreur) then
      Exit('');
  Result := FAccessToken;
end;

procedure TGoogleAuth.InvaliderAccessToken;
begin
  FAccessToken := '';
  FExpiration := 0;
end;

function TGoogleAuth.JetonEnCacheValide: Boolean;
begin
  Result := (FAccessToken <> '') and (Now < FExpiration);
end;

procedure TGoogleAuth.SauverDansFichier(const AFichier: string);
var
  J: TJSONObject;
begin
  J := TJSONObject.Create;
  try
    J.AddPair('access_token', FAccessToken);
    J.AddPair('refresh_token', FRefreshToken);
    J.AddPair('expiration', TJSONNumber.Create(DateTimeToUnix(FExpiration, False)));
    TFile.WriteAllText(AFichier, J.ToJSON);
  finally
    J.Free;
  end;
end;

procedure TGoogleAuth.ChargerDepuisFichier(const AFichier: string);
var
  NotFound: Boolean;
  J: TJSONValue;
  Expire: Double;
begin
  if not FileExists(AFichier) then
    Exit;
  J := TJSONObject.ParseJSONValue(TFile.ReadAllText(AFichier));
  if J = nil then
    Exit;
  try
    J.TryGetValue<string>('access_token', FAccessToken);
    J.TryGetValue<string>('refresh_token', FRefreshToken);
    NotFound := not J.TryGetValue<Double>('expiration', Expire);
    if not NotFound and (Expire > 0) then
      FExpiration := UnixToDateTime(Trunc(Expire), False);
  finally
    J.Free;
  end;
end;

end.

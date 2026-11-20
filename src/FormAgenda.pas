unit FormAgenda;

{ Fiche de démonstration : connexion à Google, liste des calendriers,
  suppression d'un calendrier.
  Renseignez CLIENT_ID et CLIENT_SECRET (Console Google Cloud > Identifiants)
  et ajoutez l'URI de redirection http://localhost:8099/ au client OAuth. }

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.StrUtils,
  System.IOUtils, System.Classes, System.UITypes,
  VCL.Graphics, VCL.Controls, VCL.Forms, VCL.StdCtrls,
  GoogleAuth, GoogleCalendar;

type
  TFormAgenda = class(TForm)
    lblEtat: TLabel;
    btnConnexion: TButton;
    btnLister: TButton;
    btnSupprimer: TButton;
    lsbCalendriers: TListBox;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnConnexionClick(Sender: TObject);
    procedure btnListerClick(Sender: TObject);
    procedure btnSupprimerClick(Sender: TObject);
  strict private
    FAuth: TGoogleAuth;
    FCal: TGoogleCalendrier;
    FCalendriers: TArray<TInfoCalendrier>;
    function FichierJeton: string;
  end;

var
  FormAgenda: TFormAgenda;

implementation

{$R *.dfm}

const
  CLIENT_ID     = 'VOTRE_CLIENT_ID.apps.googleusercontent.com';
  CLIENT_SECRET = 'VOTRE_CLIENT_SECRET';

function TFormAgenda.FichierJeton: string;
begin
  Result := TPath.Combine(TPath.GetHomePath, 'GoogleCal.token.json');
end;

procedure TFormAgenda.FormCreate(Sender: TObject);
begin
  FAuth := TGoogleAuth.Create(CLIENT_ID, CLIENT_SECRET);
  FAuth.ChargerDepuisFichier(FichierJeton);
  FCal := TGoogleCalendrier.Create(FAuth);
  btnLister.Enabled := False;
  btnSupprimer.Enabled := False;
  if FAuth.JetonEnCacheValide then
  begin
    lblEtat.Caption := 'Connecté (jeton en cache).';
    btnLister.Enabled := True;
  end;
end;

procedure TFormAgenda.FormDestroy(Sender: TObject);
begin
  FCal.Free;
  FAuth.Free;
end;

procedure TFormAgenda.btnConnexionClick(Sender: TObject);
var
  Erreur: string;
begin
  if not FAuth.SeConnecter(SCOPE_AGENDA, Erreur) then
  begin
    lblEtat.Caption := 'Non connecté : ' + Erreur;
    Exit;
  end;
  FAuth.SauverDansFichier(FichierJeton);
  lblEtat.Caption := 'Connecté.';
  btnLister.Enabled := True;
  btnLister.Click;
end;

procedure TFormAgenda.btnListerClick(Sender: TObject);
var
  i: Integer;
begin
  lsbCalendriers.Clear;
  FCalendriers := FCal.ListerCalendriers;
  if FCal.DerniereErreur <> '' then
  begin
    ShowMessage(FCal.DerniereErreur);
    if FCal.DernierStatut = 401 then
    begin
      lblEtat.Caption := 'Non connecté.';
      btnLister.Enabled := False;
      btnSupprimer.Enabled := False;
    end;
    Exit;
  end;

  lsbCalendriers.Items.BeginUpdate;
  try
    for i := 0 to High(FCalendriers) do
      lsbCalendriers.Items.AddObject(
        FCalendriers[i].Nom +
        IfThen(FCalendriers[i].EstPrincipal, '  (principal)', '') +
        IfThen(FCalendriers[i].PeutSupprimer, '', '  [non supprimable]'),
        TObject(NativeInt(i)));
  finally
    lsbCalendriers.Items.EndUpdate;
  end;
  btnSupprimer.Enabled := lsbCalendriers.Count > 0;
end;

procedure TFormAgenda.btnSupprimerClick(Sender: TObject);
var
  Idx: NativeInt;
  C: TInfoCalendrier;
begin
  if lsbCalendriers.ItemIndex < 0 then
  begin
    ShowMessage('Sélectionnez d''abord un calendrier dans la liste.');
    Exit;
  end;
  Idx := NativeInt(lsbCalendriers.Items.Objects[lsbCalendriers.ItemIndex]);
  C := FCalendriers[Idx];

  if C.EstPrincipal then
  begin
    ShowMessage('Le calendrier principal ne peut pas être supprimé.');
    Exit;
  end;

  if C.PeutSupprimer then
  begin
    if MessageDlg(Format('Supprimer définitivement le calendrier « %s » ?' + sLineBreak +
        'Ses événements seront perdus.', [C.Nom]),
        mtWarning, [mbYes, mbNo], 0) <> mrYes then
      Exit;
    if FCal.SupprimerCalendrier(C.Id) then
      ShowMessage('Calendrier supprimé.')
    else
      ShowMessage('Échec de la suppression : ' + FCal.DerniereErreur);
  end
  else
  begin
    if MessageDlg(Format('Vous n''êtes pas propriétaire de « %s ».' + sLineBreak +
        'Le retirer seulement de votre liste ?', [C.Nom]),
        mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;
    if FCal.RetirerDeLaListe(C.Id) then
      ShowMessage('Calendrier retiré de votre liste.')
    else
      ShowMessage('Échec : ' + FCal.DerniereErreur);
  end;

  btnLister.Click;
end;

end.

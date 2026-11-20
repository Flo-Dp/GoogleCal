program GoogleCal;

uses
  VCL.Forms,
  FormAgenda in 'src\FormAgenda.pas' {FormAgenda},
  GoogleAuth in 'src\GoogleAuth.pas',
  GoogleCalendar in 'src\GoogleCalendar.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'Agenda Google';
  Application.CreateForm(TFormAgenda, FormAgenda);
  Application.Run;
end.

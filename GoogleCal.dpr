program GoogleCal;

uses
  VCL.Forms,
  Agenda in 'src\Agenda.pas' {FormAgenda},
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

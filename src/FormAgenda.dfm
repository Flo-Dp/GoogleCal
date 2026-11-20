object FormAgenda: TFormAgenda
  Left = 0
  Top = 0
  Caption = 'Agenda Google'
  ClientHeight = 440
  ClientWidth = 620
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 15
  object lblEtat: TLabel
    Left = 16
    Top = 16
    Width = 78
    Height = 15
    Caption = 'Non connect'#233
  end
  object btnConnexion: TButton
    Left = 16
    Top = 40
    Width = 170
    Height = 33
    Caption = 'Se connecter '#224' Google'
    TabOrder = 0
    OnClick = btnConnexionClick
  end
  object btnLister: TButton
    Left = 192
    Top = 40
    Width = 170
    Height = 33
    Caption = 'Lister les calendriers'
    Enabled = False
    TabOrder = 1
    OnClick = btnListerClick
  end
  object btnSupprimer: TButton
    Left = 368
    Top = 40
    Width = 170
    Height = 33
    Caption = 'Supprimer'
    Enabled = False
    TabOrder = 2
    OnClick = btnSupprimerClick
  end
  object lsbCalendriers: TListBox
    Left = 16
    Top = 89
    Width = 522
    Height = 334
    ItemHeight = 15
    TabOrder = 3
  end
end

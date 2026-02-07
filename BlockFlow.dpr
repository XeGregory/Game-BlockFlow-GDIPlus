program BlockFlow;

uses
  Vcl.Forms,
  UBlockFlow in 'UBlockFlow.pas' {FBlockFlow};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TFBlockFlow, FBlockFlow);
  Application.Run;
end.

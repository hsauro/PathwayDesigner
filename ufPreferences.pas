unit ufPreferences;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Layouts,
  FMX.Controls.Presentation, FMX.StdCtrls, FMX.TabControl, FMX.Objects;

type
  TfrmPreferences = class(TForm)
    Layout2: TLayout;
    TabControl1: TTabControl;
    tabPreferences: TTabItem;
    btnOK: TButton;
    btnCancel: TButton;
    Rectangle1: TRectangle;
    chkConvertCatalyticReaction: TCheckBox;
    chkShowNullSpecies: TCheckBox;
    procedure btnCancelClick(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure chkConvertCatalyticReactionChange(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  frmPreferences: TfrmPreferences;

implementation

{$R *.fmx}

procedure TfrmPreferences.btnCancelClick(Sender: TObject);
begin
  ModalResult := mrCancel
end;

procedure TfrmPreferences.btnOKClick(Sender: TObject);
begin
  ModalResult := mrOk; // Save settings logic here
end;

procedure TfrmPreferences.chkConvertCatalyticReactionChange(Sender: TObject);
begin
  //if chkConvertCatalyticReaction.IsChecked then
  //   TAntimonyBridge.ConvertCatalyticSpecies := True
 // else
  //  TAntimonyBridge.ConvertCatalyticSpecies := False;
end;

procedure TfrmPreferences.FormCreate(Sender: TObject);
begin
  Rectangle1.Fill.Color := $FFF0F0F0;
end;

end.

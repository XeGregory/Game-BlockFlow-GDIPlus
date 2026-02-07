unit UBlockFlow;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, Vcl.Controls, Vcl.Forms,
  System.Math, Vcl.ExtCtrls, Vcl.Graphics, System.Types, Winapi.GDIPAPI,
  Winapi.GDIPOBJ;

type
  TCellState = (csEmpty, csFilled);
  TBoard = array [0 .. 10, 0 .. 10] of TCellState;

  TPieceShape = array of TPoint;

  TPiece = record
    Shape: TPieceShape;
    Color: TGPColor;
    PixelX, PixelY: Integer;
    InPalette: Boolean;
  end;

  TFBlockFlow = class(TForm)
    PaintBox1: TPaintBox;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure PaintBox1Paint(Sender: TObject);
    procedure PaintBox1MouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PaintBox1MouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: Integer);
    procedure PaintBox1MouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure FormResize(Sender: TObject);
  private
    FGdiPlusToken: ULONG_PTR;
    FBoard: TBoard;
    FBoardColor: array [0 .. 10, 0 .. 10] of TGPColor;
    FCellSize: Integer;
    FOffsetX, FOffsetY: Integer;
    FPalette: array of TPiece;
    FDraggingIndex: Integer;
    FDragOffset: TPoint;
    FScore: Integer;
    FPreviewCellX: Integer;
    FPreviewCellY: Integer;
    FPreviewValid: Boolean;
    FGameOver: Boolean;

    function FlatColor(A, R, G, B: Byte): TGPColor;
    function FlatColorRGB(R, G, B: Byte): TGPColor;

    procedure InitRandomPalette;
    function CreateRandomPiece: TPiece;
    procedure DrawBoard(G: TGPGraphics);
    procedure DrawPaletteBottom(G: TGPGraphics);
    function PixelToCell(px, py: Integer; out cx, cy: Integer): Boolean;
    function CanPlace(const P: TPiece; BoardX, BoardY: Integer): Boolean;
    procedure PlacePiece(const P: TPiece; BoardX, BoardY: Integer);
    function CheckAndClearLines: Integer;
    procedure ResetBoard;
    procedure RemovePaletteIndex(idx: Integer);
    procedure UpdateLayout;
    function HasAnyValidMove: Boolean;
    procedure RotatePieceInPalette(idx: Integer);
    procedure NormalizeShape(var S: TPieceShape);
  end;

var
  FBlockFlow: TFBlockFlow;

implementation

{$R *.dfm}

{ Helpers }
function TFBlockFlow.FlatColor(A, R, G, B: Byte): TGPColor;
begin
  Result := TGPColor((Cardinal(A) shl 24) or (Cardinal(R) shl 16) or
    (Cardinal(G) shl 8) or Cardinal(B));
end;

function TFBlockFlow.FlatColorRGB(R, G, B: Byte): TGPColor;
begin
  Result := FlatColor(255, R, G, B);
end;

procedure TFBlockFlow.FormCreate(Sender: TObject);
var
  StartupInput: TGdiplusStartupInput;
  Status: TStatus;
begin
  StartupInput.GdiplusVersion := 1;
  StartupInput.DebugEventCallback := nil;
  StartupInput.SuppressBackgroundThread := False;
  StartupInput.SuppressExternalCodecs := False;
  FGdiPlusToken := 0;
  Status := GdiplusStartup(FGdiPlusToken, @StartupInput, nil);
  if Status <> Ok then
    raise Exception.CreateFmt('GDI+ initialization failed (code %d)',
      [Integer(Status)]);

  Randomize;
  FCellSize := 36;
  FDraggingIndex := -1;
  FScore := 0;
  FPreviewCellX := -1;
  FPreviewCellY := -1;
  FPreviewValid := False;
  FGameOver := False;

  ResetBoard;
  InitRandomPalette;

  PaintBox1.Align := alNone;
  PaintBox1.Left := 0;
  PaintBox1.Top := 0;
  PaintBox1.Width := ClientWidth;
  PaintBox1.Height := ClientHeight;

  PaintBox1.OnPaint := PaintBox1Paint;
  PaintBox1.OnMouseDown := PaintBox1MouseDown;
  PaintBox1.OnMouseMove := PaintBox1MouseMove;
  PaintBox1.OnMouseUp := PaintBox1MouseUp;

  OnResize := FormResize;
end;

procedure TFBlockFlow.FormDestroy(Sender: TObject);
begin
  if FGdiPlusToken <> 0 then
    GdiplusShutdown(FGdiPlusToken);
end;

procedure TFBlockFlow.FormResize(Sender: TObject);
begin
  PaintBox1.BoundsRect := Rect(0, 0, ClientWidth, ClientHeight);
  PaintBox1.Invalidate;
end;

procedure TFBlockFlow.ResetBoard;
var
  i, j: Integer;
begin
  for i := 0 to 10 do
    for j := 0 to 10 do
    begin
      FBoard[i, j] := csEmpty;
      FBoardColor[i, j] := FlatColor(0, 0, 0, 0);
    end;
end;

procedure TFBlockFlow.NormalizeShape(var S: TPieceShape);
var
  i, minX, minY: Integer;
begin
  if Length(S) = 0 then
    Exit;
  minX := S[0].X;
  minY := S[0].Y;
  for i := 1 to High(S) do
  begin
    if S[i].X < minX then
      minX := S[i].X;
    if S[i].Y < minY then
      minY := S[i].Y;
  end;
  if (minX = 0) and (minY = 0) then
    Exit;
  for i := 0 to High(S) do
  begin
    S[i].X := S[i].X - minX;
    S[i].Y := S[i].Y - minY;
  end;
end;

function TFBlockFlow.CreateRandomPiece: TPiece;
var
  kind: Integer;
  P: TPiece;
begin
  kind := Random(10);
  case kind of
    0:
      begin
        SetLength(P.Shape, 3);
        P.Shape[0] := Point(0, 0);
        P.Shape[1] := Point(1, 0);
        P.Shape[2] := Point(2, 0);
        P.Color := FlatColorRGB(0, 188, 212);
      end;
    1: // O
      begin
        SetLength(P.Shape, 4);
        P.Shape[0] := Point(0, 0);
        P.Shape[1] := Point(1, 0);
        P.Shape[2] := Point(0, 1);
        P.Shape[3] := Point(1, 1);
        P.Color := FlatColorRGB(255, 193, 7);
      end;
    2: // T
      begin
        SetLength(P.Shape, 4);
        P.Shape[0] := Point(0, 0);
        P.Shape[1] := Point(1, 0);
        P.Shape[2] := Point(2, 0);
        P.Shape[3] := Point(1, 1);
        P.Color := FlatColorRGB(156, 39, 176);
      end;
    3: // S
      begin
        SetLength(P.Shape, 4);
        P.Shape[0] := Point(1, 0);
        P.Shape[1] := Point(2, 0);
        P.Shape[2] := Point(0, 1);
        P.Shape[3] := Point(1, 1);
        P.Color := FlatColorRGB(76, 175, 80);
      end;
    4: // Z
      begin
        SetLength(P.Shape, 4);
        P.Shape[0] := Point(0, 0);
        P.Shape[1] := Point(1, 0);
        P.Shape[2] := Point(1, 1);
        P.Shape[3] := Point(2, 1);
        P.Color := FlatColorRGB(244, 67, 54);
      end;
    5: // J
      begin
        SetLength(P.Shape, 4);
        P.Shape[0] := Point(0, 0);
        P.Shape[1] := Point(0, 1);
        P.Shape[2] := Point(1, 1);
        P.Shape[3] := Point(2, 1);
        P.Color := FlatColorRGB(33, 150, 243);
      end;
    6: // L
      begin
        SetLength(P.Shape, 4);
        P.Shape[0] := Point(2, 0);
        P.Shape[1] := Point(0, 1);
        P.Shape[2] := Point(1, 1);
        P.Shape[3] := Point(2, 1);
        P.Color := FlatColorRGB(255, 152, 0);
      end;
    7: // Single
      begin
        SetLength(P.Shape, 1);
        P.Shape[0] := Point(0, 0);
        P.Color := FlatColorRGB(96, 125, 139);
      end;
    8: // Zigzag 5
      begin
        SetLength(P.Shape, 5);
        P.Shape[0] := Point(1, 0);
        P.Shape[1] := Point(2, 0);
        P.Shape[2] := Point(0, 1);
        P.Shape[3] := Point(1, 1);
        P.Shape[4] := Point(0, 2);
        P.Color := FlatColorRGB(255, 87, 34);
      end;
    9: // Croix (plus)
      begin
        SetLength(P.Shape, 5);
        P.Shape[0] := Point(1, 0);
        P.Shape[1] := Point(0, 1);
        P.Shape[2] := Point(1, 1);
        P.Shape[3] := Point(2, 1);
        P.Shape[4] := Point(1, 2);
        P.Color := FlatColorRGB(233, 30, 99);
      end;
  else
    begin
      SetLength(P.Shape, 1);
      P.Shape[0] := Point(0, 0);
      P.Color := FlatColorRGB(158, 158, 158);
    end;
  end;
  NormalizeShape(P.Shape);
  P.InPalette := True;
  P.PixelX := 0;
  P.PixelY := 0;
  Result := P;
end;

procedure TFBlockFlow.InitRandomPalette;
var
  i: Integer;
begin
  SetLength(FPalette, 0);
  for i := 0 to 1 do
  begin
    SetLength(FPalette, Length(FPalette) + 1);
    FPalette[High(FPalette)] := CreateRandomPiece;
  end;
  FGameOver := not HasAnyValidMove;
end;

procedure TFBlockFlow.RemovePaletteIndex(idx: Integer);
var
  i: Integer;
begin
  if (idx < 0) or (idx > High(FPalette)) then
    Exit;
  for i := idx to High(FPalette) - 1 do
    FPalette[i] := FPalette[i + 1];
  SetLength(FPalette, Length(FPalette) - 1);
  if Length(FPalette) = 0 then
  begin
    InitRandomPalette;
  end
  else
  begin
    if not HasAnyValidMove then
      FGameOver := True;
  end;
end;

procedure TFBlockFlow.UpdateLayout;
var
  gridW, gridH, paletteH, totalH: Integer;
  clientW, clientH: Integer;
begin
  clientW := Self.ClientWidth;
  clientH := Self.ClientHeight;

  gridW := 11 * FCellSize;
  gridH := 11 * FCellSize;
  paletteH := FCellSize * 3 + 24;
  totalH := gridH + paletteH + 48;

  FOffsetX := (clientW - gridW) div 2;
  if FOffsetX < 8 then
    FOffsetX := 8;

  FOffsetY := (clientH - totalH) div 2 + 24;
  if FOffsetY < 8 then
    FOffsetY := 8;
end;

procedure TFBlockFlow.DrawBoard(G: TGPGraphics);
var
  i, j: Integer;
  Rect: TGPRectF;
  penGrid: TGPPen;
  brushCell: TGPSolidBrush;
  boardBg: TGPSolidBrush;
begin
  penGrid := TGPPen.Create(FlatColorRGB(224, 224, 224), 1);
  try
    boardBg := TGPSolidBrush.Create(FlatColorRGB(250, 250, 250));
    try
      Rect.X := FOffsetX - 4;
      Rect.Y := FOffsetY - 4;
      Rect.Width := 11 * FCellSize + 8;
      Rect.Height := 11 * FCellSize + 8;
      G.FillRectangle(boardBg, Rect);
    finally
      boardBg.Free;
    end;

    for i := 0 to 10 do
      for j := 0 to 10 do
      begin
        Rect.X := FOffsetX + i * FCellSize;
        Rect.Y := FOffsetY + j * FCellSize;
        Rect.Width := FCellSize;
        Rect.Height := FCellSize;
        if FBoard[i, j] = csFilled then
        begin
          brushCell := TGPSolidBrush.Create(FBoardColor[i, j]);
          try
            G.FillRectangle(brushCell, Rect);
          finally
            brushCell.Free;
          end;
        end
        else
        begin
          brushCell := TGPSolidBrush.Create(FlatColorRGB(245, 245, 245));
          try
            G.FillRectangle(brushCell, Rect);
          finally
            brushCell.Free;
          end;
        end;
        G.DrawRectangle(penGrid, Rect);
      end;
  finally
    penGrid.Free;
  end;
end;

procedure TFBlockFlow.DrawPaletteBottom(G: TGPGraphics);
var
  idx, i: Integer;
  slotW, slotH, spacing: Integer;
  startX, startY: Integer;
  R: TGPRectF;
  piece: TPiece;
  px, py: Integer;
  cellBrush: TGPSolidBrush;
  minX, minY, maxX, maxY: Integer;
  wCells, hCells: Integer;
  gridW: Integer;
  slotsCount: Integer;
  totalSlotsWidth, leftMargin: Integer;
  maxPieceW, maxPieceH: Integer;
begin
  gridW := 11 * FCellSize;
  slotsCount := Max(Length(FPalette), 1);
  spacing := 12;

  maxPieceW := 1;
  maxPieceH := 1;
  for idx := 0 to High(FPalette) do
  begin
    if Length(FPalette[idx].Shape) = 0 then
      Continue;
    minX := FPalette[idx].Shape[0].X;
    maxX := FPalette[idx].Shape[0].X;
    minY := FPalette[idx].Shape[0].Y;
    maxY := FPalette[idx].Shape[0].Y;
    for i := 1 to High(FPalette[idx].Shape) do
    begin
      if FPalette[idx].Shape[i].X < minX then
        minX := FPalette[idx].Shape[i].X;
      if FPalette[idx].Shape[i].X > maxX then
        maxX := FPalette[idx].Shape[i].X;
      if FPalette[idx].Shape[i].Y < minY then
        minY := FPalette[idx].Shape[i].Y;
      if FPalette[idx].Shape[i].Y > maxY then
        maxY := FPalette[idx].Shape[i].Y;
    end;
    wCells := maxX - minX + 1;
    hCells := maxY - minY + 1;
    if wCells > maxPieceW then
      maxPieceW := wCells;
    if hCells > maxPieceH then
      maxPieceH := hCells;
  end;

  slotW := Max(maxPieceW, 4) * FCellSize;
  slotH := Max(maxPieceH, 3) * FCellSize;

  startX := FOffsetX;
  startY := FOffsetY + 11 * FCellSize + 12;

  R.X := startX - 4;
  R.Y := startY - 8;
  R.Width := gridW + 8;
  R.Height := slotH + 16;
  cellBrush := TGPSolidBrush.Create(FlatColorRGB(250, 250, 250));
  try
    G.FillRectangle(cellBrush, R);
  finally
    cellBrush.Free;
  end;

  totalSlotsWidth := slotsCount * slotW + Max(0, slotsCount - 1) * spacing;
  leftMargin := (gridW - totalSlotsWidth) div 2;
  if leftMargin < 0 then
    leftMargin := 0;

  for idx := 0 to High(FPalette) do
  begin
    piece := FPalette[idx];

    if Length(piece.Shape) = 0 then
    begin
      minX := 0;
      minY := 0;
      maxX := 0;
      maxY := 0;
    end
    else
    begin
      minX := piece.Shape[0].X;
      maxX := piece.Shape[0].X;
      minY := piece.Shape[0].Y;
      maxY := piece.Shape[0].Y;
      for i := 1 to High(piece.Shape) do
      begin
        if piece.Shape[i].X < minX then
          minX := piece.Shape[i].X;
        if piece.Shape[i].X > maxX then
          maxX := piece.Shape[i].X;
        if piece.Shape[i].Y < minY then
          minY := piece.Shape[i].Y;
        if piece.Shape[i].Y > maxY then
          maxY := piece.Shape[i].Y;
      end;
    end;

    wCells := maxX - minX + 1;
    hCells := maxY - minY + 1;

    px := startX + leftMargin + idx * (slotW + spacing);
    px := px + (slotW - wCells * FCellSize) div 2;
    py := startY + (slotH - hCells * FCellSize) div 2;

    for i := 0 to High(piece.Shape) do
    begin
      R.X := px + (piece.Shape[i].X - minX) * FCellSize;
      R.Y := py + (piece.Shape[i].Y - minY) * FCellSize;
      R.Width := FCellSize;
      R.Height := FCellSize;

      cellBrush := TGPSolidBrush.Create(piece.Color);
      try
        G.FillRectangle(cellBrush, R);
      finally
        cellBrush.Free;
      end;
    end;

    FPalette[idx].PixelX := px;
    FPalette[idx].PixelY := py;
  end;
end;

procedure TFBlockFlow.PaintBox1Paint(Sender: TObject);
var
  G: TGPGraphics;
  titleBrush: TGPSolidBrush;
  titleFont: TGPFont;
  titleFormat: TGPStringFormat;
  titleRect: TGPRectF;
  scoreText: string;
  i: Integer;
  piece: TPiece;
  previewBrush: TGPSolidBrush;
  R: TGPRectF;
  col: Cardinal;
  cA, cR, cG, cB: Byte;
  colARGB: Cardinal;
  floatingBrush: TGPSolidBrush;
  pen: TGPPen;
  overlayBrush: TGPSolidBrush;
  overlayFormat: TGPStringFormat;
  overlayRect: TGPRectF;
  familyTitle: TGPFontFamily;
  fontTitle: TGPFont;
  familyInstr: TGPFontFamily;
  fontInstr: TGPFont;
begin
  G := TGPGraphics.Create(PaintBox1.Canvas.Handle);
  try
    G.SetSmoothingMode(SmoothingModeAntiAlias);
    UpdateLayout;

    G.Clear(FlatColorRGB(236, 240, 241));
    scoreText := 'Score: ' + IntToStr(FScore);
    titleFormat := TGPStringFormat.Create;
    try
      titleFormat.SetAlignment(StringAlignmentCenter);
      titleFormat.SetLineAlignment(StringAlignmentCenter);
      titleRect.X := FOffsetX;
      titleRect.Y := FOffsetY - 40;
      titleRect.Width := 11 * FCellSize;
      titleRect.Height := 32;
      titleBrush := TGPSolidBrush.Create(FlatColorRGB(33, 33, 33));
      try
        titleFont := TGPFont.Create('Segoe UI', 14, FontStyleBold, UnitPixel);
        try
          G.DrawString(PWideChar(scoreText), -1, titleFont, titleRect,
            titleFormat, titleBrush);
        finally
          titleFont.Free;
        end;
      finally
        titleBrush.Free;
      end;
    finally
      titleFormat.Free;
    end;

    DrawBoard(G);
    DrawPaletteBottom(G);

    if (FDraggingIndex >= 0) and (FPreviewCellX >= 0) and (FPreviewCellY >= 0)
      and (FDraggingIndex <= High(FPalette)) then
    begin
      piece := FPalette[FDraggingIndex];
      if FPreviewValid then
      begin
        cA := 120;
        cR := 76;
        cG := 175;
        cB := 80;
      end
      else
      begin
        cA := 120;
        cR := 244;
        cG := 67;
        cB := 54;
      end;
      colARGB := (Cardinal(cA) shl 24) or (Cardinal(cR) shl 16) or
        (Cardinal(cG) shl 8) or Cardinal(cB);
      previewBrush := TGPSolidBrush.Create(TGPColor(colARGB));
      try
        for i := 0 to High(piece.Shape) do
        begin
          R.X := FOffsetX + (FPreviewCellX + piece.Shape[i].X) * FCellSize;
          R.Y := FOffsetY + (FPreviewCellY + piece.Shape[i].Y) * FCellSize;
          R.Width := FCellSize;
          R.Height := FCellSize;
          G.FillRectangle(previewBrush, R);
        end;
      finally
        previewBrush.Free;
      end;
    end;

    if (FDraggingIndex >= 0) and (FDraggingIndex <= High(FPalette)) then
    begin
      piece := FPalette[FDraggingIndex];
      col := Cardinal(piece.Color);
      cR := Byte((col shr 16) and $FF);
      cG := Byte((col shr 8) and $FF);
      cB := Byte(col and $FF);
      cA := 200;
      colARGB := (Cardinal(cA) shl 24) or (Cardinal(cR) shl 16) or
        (Cardinal(cG) shl 8) or Cardinal(cB);
      floatingBrush := TGPSolidBrush.Create(TGPColor(colARGB));
      pen := TGPPen.Create(FlatColorRGB(120, 144, 156), 1);
      try
        for i := 0 to High(piece.Shape) do
        begin
          R.X := piece.PixelX + piece.Shape[i].X * FCellSize;
          R.Y := piece.PixelY + piece.Shape[i].Y * FCellSize;
          R.Width := FCellSize;
          R.Height := FCellSize;
          G.FillRectangle(floatingBrush, R);
          G.DrawRectangle(pen, R);
        end;
      finally
        pen.Free;
        floatingBrush.Free;
      end;
    end;

    if FGameOver then
    begin
      overlayBrush := TGPSolidBrush.Create
        (TGPColor((Cardinal(160) shl 24) or (Cardinal(0) shl 16) or
        (Cardinal(0) shl 8) or Cardinal(0)));
      try
        R.X := FOffsetX;
        R.Y := FOffsetY;
        R.Width := 11 * FCellSize;
        R.Height := 11 * FCellSize;
        G.FillRectangle(overlayBrush, R);
      finally
        overlayBrush.Free;
      end;

      overlayFormat := TGPStringFormat.Create;
      try
        overlayFormat.SetAlignment(StringAlignmentCenter);
        overlayFormat.SetLineAlignment(StringAlignmentCenter);

        overlayRect.X := FOffsetX;
        overlayRect.Y := FOffsetY + (11 * FCellSize) / 2 - 40;
        overlayRect.Width := 11 * FCellSize;
        overlayRect.Height := 40;

        familyTitle := TGPFontFamily.Create('Segoe UI');
        fontTitle := TGPFont.Create(familyTitle, 20, FontStyleBold, UnitPixel);
        overlayBrush := TGPSolidBrush.Create(FlatColorRGB(255, 255, 255));
        try
          G.DrawString(PWideChar('Game Over'), -1, fontTitle, overlayRect,
            overlayFormat, overlayBrush);
        finally
          overlayBrush.Free;
          fontTitle.Free;
          familyTitle.Free;
        end;

        overlayRect.Y := overlayRect.Y + 44;
        overlayRect.Height := 36;

        familyInstr := TGPFontFamily.Create('Segoe UI');
        fontInstr := TGPFont.Create(familyInstr, 10, FontStyleRegular,
          UnitPixel);
        overlayBrush := TGPSolidBrush.Create(FlatColorRGB(255, 255, 255));
        try
          G.DrawString(PWideChar('Cliquez pour recommencer'), -1, fontInstr,
            overlayRect, overlayFormat, overlayBrush);
        finally
          overlayBrush.Free;
          fontInstr.Free;
          familyInstr.Free;
        end;

      finally
        overlayFormat.Free;
      end;
    end;

  finally
    G.Free;
  end;
end;

function TFBlockFlow.PixelToCell(px, py: Integer; out cx, cy: Integer): Boolean;
begin
  cx := (px - FOffsetX) div FCellSize;
  cy := (py - FOffsetY) div FCellSize;
  Result := (cx >= 0) and (cx <= 10) and (cy >= 0) and (cy <= 10);
end;

function TFBlockFlow.CanPlace(const P: TPiece; BoardX, BoardY: Integer)
  : Boolean;
var
  i, X, Y: Integer;
begin
  Result := False;
  for i := 0 to High(P.Shape) do
  begin
    X := BoardX + P.Shape[i].X;
    Y := BoardY + P.Shape[i].Y;
    if (X < 0) or (X > 10) or (Y < 0) or (Y > 10) then
      Exit;
    if FBoard[X, Y] = csFilled then
      Exit;
  end;
  Result := True;
end;

procedure TFBlockFlow.PlacePiece(const P: TPiece; BoardX, BoardY: Integer);
var
  i, X, Y: Integer;
begin
  for i := 0 to High(P.Shape) do
  begin
    X := BoardX + P.Shape[i].X;
    Y := BoardY + P.Shape[i].Y;
    FBoard[X, Y] := csFilled;
    FBoardColor[X, Y] := P.Color;
  end;
end;

function TFBlockFlow.CheckAndClearLines: Integer;
var
  i, j, cleared: Integer;
  full: Boolean;
begin
  cleared := 0;
  for j := 0 to 10 do
  begin
    full := True;
    for i := 0 to 10 do
      if FBoard[i, j] = csEmpty then
      begin
        full := False;
        Break;
      end;
    if full then
    begin
      Inc(cleared);
      for i := 0 to 10 do
      begin
        FBoard[i, j] := csEmpty;
        FBoardColor[i, j] := FlatColor(0, 0, 0, 0);
      end;
    end;
  end;
  for i := 0 to 10 do
  begin
    full := True;
    for j := 0 to 10 do
      if FBoard[i, j] = csEmpty then
      begin
        full := False;
        Break;
      end;
    if full then
    begin
      Inc(cleared);
      for j := 0 to 10 do
      begin
        FBoard[i, j] := csEmpty;
        FBoardColor[i, j] := FlatColor(0, 0, 0, 0);
      end;
    end;
  end;
  Result := cleared;
end;

function TFBlockFlow.HasAnyValidMove: Boolean;
var
  idx, cx, cy: Integer;
begin
  Result := False;
  if Length(FPalette) = 0 then
    Exit;
  for idx := 0 to High(FPalette) do
  begin
    for cx := 0 to 10 do
      for cy := 0 to 10 do
        if CanPlace(FPalette[idx], cx, cy) then
        begin
          Result := True;
          Exit;
        end;
  end;
end;

procedure TFBlockFlow.RotatePieceInPalette(idx: Integer);
var
  i: Integer;
  S: TPieceShape;
  nx, ny: Integer;
begin
  if (idx < 0) or (idx > High(FPalette)) then
    Exit;
  S := FPalette[idx].Shape;
  for i := 0 to High(S) do
  begin
    nx := -S[i].Y;
    ny := S[i].X;
    S[i].X := nx;
    S[i].Y := ny;
  end;
  NormalizeShape(S);
  FPalette[idx].Shape := S;
  PaintBox1.Invalidate;
end;

procedure TFBlockFlow.PaintBox1MouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  idx, px, py, slotW, slotH, spacing: Integer;
  i, minX, minY, maxX, maxY: Integer;
  gridW, slotsCount, totalSlotsWidth, leftMargin: Integer;
  boxW, boxH: Integer;
  maxPieceW, maxPieceH, wCells, hCells: Integer;
begin
  if FGameOver then
  begin
    ResetBoard;
    FScore := 0;
    InitRandomPalette;
    FGameOver := False;
    PaintBox1.Invalidate;
    Exit;
  end;

  gridW := 11 * FCellSize;
  slotsCount := Max(Length(FPalette), 1);
  spacing := 12;

  maxPieceW := 1;
  maxPieceH := 1;
  for idx := 0 to High(FPalette) do
  begin
    if Length(FPalette[idx].Shape) = 0 then
      Continue;
    minX := FPalette[idx].Shape[0].X;
    maxX := FPalette[idx].Shape[0].X;
    minY := FPalette[idx].Shape[0].Y;
    maxY := FPalette[idx].Shape[0].Y;
    for i := 1 to High(FPalette[idx].Shape) do
    begin
      if FPalette[idx].Shape[i].X < minX then
        minX := FPalette[idx].Shape[i].X;
      if FPalette[idx].Shape[i].X > maxX then
        maxX := FPalette[idx].Shape[i].X;
      if FPalette[idx].Shape[i].Y < minY then
        minY := FPalette[idx].Shape[i].Y;
      if FPalette[idx].Shape[i].Y > maxY then
        maxY := FPalette[idx].Shape[i].Y;
    end;
    wCells := maxX - minX + 1;
    hCells := maxY - minY + 1;
    if wCells > maxPieceW then
      maxPieceW := wCells;
    if hCells > maxPieceH then
      maxPieceH := hCells;
  end;

  slotW := Max(maxPieceW, 4) * FCellSize;
  slotH := Max(maxPieceH, 3) * FCellSize;

  totalSlotsWidth := slotsCount * slotW + Max(0, slotsCount - 1) * spacing;
  leftMargin := (gridW - totalSlotsWidth) div 2;
  if leftMargin < 0 then
    leftMargin := 0;

  for idx := 0 to High(FPalette) do
  begin
    px := FOffsetX + leftMargin + idx * (slotW + spacing);
    py := FOffsetY + 11 * FCellSize + 12 +
      (slotH - Max(maxPieceH, 3) * FCellSize) div 2;

    boxW := slotW;
    boxH := slotH;

    if (X >= px) and (X < px + boxW) and (Y >= py) and (Y < py + boxH) then
    begin
      if Button = mbRight then
      begin
        RotatePieceInPalette(idx);
        PaintBox1.Invalidate;
        Exit;
      end
      else if Button = mbLeft then
      begin
        if Length(FPalette[idx].Shape) = 0 then
        begin
          minX := 0;
          minY := 0;
          maxX := 0;
          maxY := 0;
        end
        else
        begin
          minX := FPalette[idx].Shape[0].X;
          maxX := FPalette[idx].Shape[0].X;
          minY := FPalette[idx].Shape[0].Y;
          maxY := FPalette[idx].Shape[0].Y;
          for i := 1 to High(FPalette[idx].Shape) do
          begin
            if FPalette[idx].Shape[i].X < minX then
              minX := FPalette[idx].Shape[i].X;
            if FPalette[idx].Shape[i].X > maxX then
              maxX := FPalette[idx].Shape[i].X;
            if FPalette[idx].Shape[i].Y < minY then
              minY := FPalette[idx].Shape[i].Y;
            if FPalette[idx].Shape[i].Y > maxY then
              maxY := FPalette[idx].Shape[i].Y;
          end;
        end;
        wCells := maxX - minX + 1;
        hCells := maxY - minY + 1;

        px := FOffsetX + leftMargin + idx * (slotW + spacing) +
          (slotW - wCells * FCellSize) div 2;
        py := FOffsetY + 11 * FCellSize + 12 +
          (slotH - hCells * FCellSize) div 2;

        FDraggingIndex := idx;
        FDragOffset.X := X - px;
        FDragOffset.Y := Y - py;
        FPalette[idx].InPalette := False;
        FPalette[idx].PixelX := X - FDragOffset.X;
        FPalette[idx].PixelY := Y - FDragOffset.Y;
        FPreviewCellX := -1;
        FPreviewCellY := -1;
        FPreviewValid := False;
        PaintBox1.Invalidate;
        Exit;
      end;
    end;
  end;
end;

procedure TFBlockFlow.PaintBox1MouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
var
  cx, cy: Integer;
begin
  if FDraggingIndex >= 0 then
  begin
    FPalette[FDraggingIndex].PixelX := X - FDragOffset.X;
    FPalette[FDraggingIndex].PixelY := Y - FDragOffset.Y;

    if PixelToCell(X, Y, cx, cy) then
    begin
      FPreviewCellX := cx;
      FPreviewCellY := cy;
      FPreviewValid := CanPlace(FPalette[FDraggingIndex], cx, cy);
    end
    else
    begin
      FPreviewCellX := -1;
      FPreviewCellY := -1;
      FPreviewValid := False;
    end;

    PaintBox1.Invalidate;
  end;
end;

procedure TFBlockFlow.PaintBox1MouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  cx, cy, cleared, placedCells: Integer;
  placedPiece: TPiece;
begin
  if FDraggingIndex >= 0 then
  begin
    if PixelToCell(X, Y, cx, cy) then
    begin
      placedPiece := FPalette[FDraggingIndex];
      if CanPlace(placedPiece, cx, cy) then
      begin
        PlacePiece(placedPiece, cx, cy);

        placedCells := Length(placedPiece.Shape);
        Inc(FScore, placedCells * 10);

        cleared := CheckAndClearLines;
        if cleared > 0 then
          Inc(FScore, cleared * 100);

        RemovePaletteIndex(FDraggingIndex);

        if not FGameOver then
        begin
          if not HasAnyValidMove then
            FGameOver := True;
        end;
      end
      else
      begin
        if (FDraggingIndex <= High(FPalette)) then
          FPalette[FDraggingIndex].InPalette := True;
      end;
    end
    else
    begin
      if (FDraggingIndex <= High(FPalette)) then
        FPalette[FDraggingIndex].InPalette := True;
    end;

    FDraggingIndex := -1;
    FPreviewCellX := -1;
    FPreviewCellY := -1;
    FPreviewValid := False;
    PaintBox1.Invalidate;
  end;
end;

end.

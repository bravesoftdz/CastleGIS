{
  Copyright 2017-2018 Yevhen Loza, Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Basic GIS operations on points and rendering of the base map
  Longtitude/Latitude is given in decimal degrees }

unit CastleGIS;

{$mode objfpc}{$H+}

interface

uses
  CastleImages, CastleVectors, CastleGLImages,
  Generics.Collections;

type
  TGeoObject = class(TObject)
  strict protected
    Latitude_to_km_ratio, Longtitude_to_km_ratio: single;

    { returns distance in km to lng,lat point }
    function AccurateDistance(aLongtitude, aLatitude: single): single;
  public
    FDepth, FLatitude, FLongtitude: single;
    FHorizontalError, FDepthError: single;
    procedure CacheLongtitudeLatitude;
  public
    procedure ParseLatitude(const aData: string);
    procedure ParseLongtitude(const aData: string);
    procedure ParseDepth(const aData: string);
  public
    function isWithinLatitude(const aValue1, aValue2: single): boolean;
    function isWithinLongtitude(const aValue1, aValue2: single): boolean;
    function isWithinDepth(const aValue1, aValue2: single): boolean;
    function Distance(aLongtitude, aLatitude: single): single;
    function Distance(const aObj: TGeoObject): single;
  end;

type
  TTimedObject = class(TGeoObject)
  strict protected
    const FTimeError = 30/60/60/24; {30 seconds}
  public
    //procedure ParseTime(const aData: string);
  public
    FTime: TDateTime;
    FEnergy: single; {in Joules}
//    property Time: TDateTime read FTime;
    function isTime(const aTime: TDateTime): boolean;
    function isWithinTime(const aTime1, aTime2: TDateTime): boolean;
  end;

type
  TReferencePointType = (rpBottomLeft, rpTopRight);

type
  { a basic rectangle, that provides a link between geographical coordinates
    and on-screen coordinates (pixels) }
  TWGS84Rectangle = class(TObject)
  public
    { Link between coordinates and WGS84 geographical coordinates
      [rpBottomLeft] should be Bottom-Left coordinate of the image and
      [rpTopRight] should be Top-Right coordinate of the image
      Otherwise the image will be drawn inversed
      These are not mandatorily the cornerpoints of the image, just two points
      that have a valid relation between pixels and geographical coordinates }
    ReferencePointImage: array [TReferencePointType] of TVector2;
    ReferencePointWGS84: array [TReferencePointType] of TVector2;

    { Default geographic span is the whole Earth }
    procedure DefaultGeoReference;

    { Useful functions to automate other routines
      raise errors in case the TWGS84Rectangle is not valid }
    function ImageWidth: single;
    function ImageHeight: single;
    function GeoWidth: single;
    function GeoHeight: single;

    { convert geographical coordinates to screen coordinates }
    function LongtitudeToX(const aLongtitude: single): single;
    function LatitudeToY(const aLatitude: single): single;
    function LngLatToXY(const aLngLat: TVector2): TVector2;

    { convert screen coordinates to geographical coordinates }
    function XToLongtitude(const aX: single): single;
    function YToLatitude(const aY: single): single;
    function XYToLngLat(const aXY: TVector2): TVector2;

    function CopyContainer: TWGS84Rectangle;
  end;

type
  TBaseMap = class(TWGS84Rectangle)
  strict private
    MapImage: TGLImage;
  public
    { Draw the Base map scaled against TWGS84Rectangle
      Both BaseMap and Container must be correctly geo-aligned
      Pay attention: there will be no drawing beyond Container.ReferencePointImage
      DrawCore just draws the map as is
      Draw wraps the map into a cylinder at Latitude = plus-minus 180 deg.}
    procedure DrawCore(Container: TWGS84Rectangle);
    procedure Draw(Container: TWGS84Rectangle);
    { Default image span is (0,0) - (MapImage.Width, MapImage.Height) }
    procedure DefaultMapReference;
  public
    constructor Create(const aURL: string);
    destructor Destroy; override;
  end;

type
  TGeoList = specialize TObjectList<TGeoObject>;
  TTimedList = specialize TObjectList<TTimedObject>;


implementation
uses
  SysUtils;

{------------------- Time ------------------------------------}

function TTimedObject.isTime(const aTime: TDateTime): boolean;
begin
  Result := (FTime + FTimeError >= aTime) and (FTime - FTimeError <= aTime);
end;

function TTimedObject.isWithinTime(const aTime1, aTime2: TDateTime): boolean;
begin
  if aTime2 > aTime1 then
    Result := (FTime + FTimeError >= aTime1) and (FTime - FTimeError <= aTime2)
  else
    Result := (FTime + FTimeError >= aTime2) and (FTime - FTimeError <= aTime1);
end;

function TGeoObject.isWithinDepth(const aValue1, aValue2: single): boolean;
begin
  if aValue2 > aValue1 then
    Result := (FDepth + FDepthError >= aValue1) and (FDepth - FDepthError <= aValue2)
  else
    Result := (FDepth + FDepthError >= aValue2) and (FDepth - FDepthError <= aValue1);
end;

function TGeoObject.isWithinLatitude(const aValue1, aValue2: single): boolean;
begin
  if aValue2 > aValue1 then
    Result := (FLatitude + FHorizontalError / Latitude_to_km_ratio >= aValue1) and (FLatitude - FHorizontalError / Latitude_to_km_ratio <= aValue2)
  else
    Result := (FLatitude + FHorizontalError / Latitude_to_km_ratio >= aValue2) and (FLatitude - FHorizontalError / Latitude_to_km_ratio <= aValue1);
end;

function TGeoObject.isWithinLongtitude(const aValue1, aValue2: single): boolean;
begin
  if aValue2 > aValue1 then
    Result := (FLongtitude + FHorizontalError / Latitude_to_km_ratio >= aValue1) and (FLongtitude - FHorizontalError / Latitude_to_km_ratio <= aValue2)
  else
    Result := (FLongtitude + FHorizontalError / Latitude_to_km_ratio >= aValue2) and (FLongtitude - FHorizontalError / Latitude_to_km_ratio <= aValue1);
end;

procedure TGeoObject.ParseLatitude(const aData: string);
begin
  FLatitude := aData.Tosingle;
end;

procedure TGeoObject.ParseLongtitude(const aData: string);
begin
  FLongtitude := aData.Tosingle;
end;

procedure TGeoObject.ParseDepth(const aData: string);
begin
  if aData <> '' then
    FDepth := aData.Tosingle
  else
    FDepth := 0;
end;

{------------------- Geo ------------------------------------}

function TGeoObject.Distance(aLongtitude, aLatitude: single): single;
var
  LngDiff: single;
begin
  LngDiff := aLongtitude - Self.FLongtitude;
  while LngDiff > 180 do
    LngDiff -= 360;
  while LngDiff < -180 do
    LngDiff += 360;

  Result := sqr((aLatitude - Self.FLatitude) * Latitude_to_km_ratio)  +
    sqr((LngDiff) * Longtitude_to_km_ratio);

  if true {Result < %n^2} then
    Result := Sqrt(Result)
  else
    Result := AccurateDistance(aLongtitude, aLatitude);
end;

function TGeoObject.Distance(const aObj: TGeoObject): single;
begin
  Result := Self.Distance(aObj.FLongtitude, aObj.FLatitude);
end;

function TGeoObject.AccurateDistance(aLongtitude, aLatitude: single): single;
begin
  //https://en.wikipedia.org/wiki/Geographical_distance
  {$WARNING todo}
  Result := 0;
end;

{--------------------- CACHING ------------------------------------}

procedure TGeoObject.CacheLongtitudeLatitude;
{formulae from Wikipedia}
const
  LatCoef0 = 111132.92;
  LatCoef2 = -559.82;
  LatCoef4 = 1.175;
  LatCoef6 = -0.0023;

  LngCoef1 = 111412.84;
  LngCoef3 = 93.5;
  LngCoef5 = 0.118;
begin
  Latitude_to_km_ratio := ((LatCoef0 + LatCoef2 * cos(2 * FLatitude/180) +
    LatCoef4 * cos(4 * FLatitude/180) + LatCoef6 * cos(6 * FLatitude/180)))/1000;
  Longtitude_to_km_ratio := ((LngCoef1 * cos(1 * FLatitude/180) +
    LngCoef3 * cos(3 * FLatitude/180) + LngCoef5 * cos(5 * FLatitude/180)))/1000;
end;

{=============== TBaseMap =========================}

function TWGS84Rectangle.ImageWidth: single;
begin
  Result := ReferencePointImage[rpTopRight][0] - ReferencePointImage[rpBottomLeft][0];

  //raise error in case the georeferencing is invalid, we'll get a division by zero anyway on the next step
  if Result = 0 then
    raise Exception.Create('Error: TWGS84Rectangle.ImageWidth = 0');
end;

function TWGS84Rectangle.ImageHeight: single;
begin
  Result := ReferencePointImage[rpTopRight][1] - ReferencePointImage[rpBottomLeft][1];

  if Result = 0 then
    raise Exception.Create('Error: TWGS84Rectangle.ImageHeight = 0');
end;

function TWGS84Rectangle.GeoWidth: single;
begin
  Result := ReferencePointWGS84[rpTopRight][0] - ReferencePointWGS84[rpBottomLeft][0];

  if Result = 0 then
    raise Exception.Create('Error: TWGS84Rectangle.GeoWidth = 0');
end;

function TWGS84Rectangle.GeoHeight: single;
begin
  Result := ReferencePointWGS84[rpTopRight][1] - ReferencePointWGS84[rpBottomLeft][1];

  if Result = 0 then
    raise Exception.Create('Error: TWGS84Rectangle.GeoHeight = 0');
end;

function TWGS84Rectangle.LongtitudeToX(const aLongtitude: single): single;
begin
  Result := ReferencePointImage[rpBottomLeft][0] +
    ((aLongtitude - ReferencePointWGS84[rpBottomLeft][0]) * ImageWidth / GeoWidth);
end;

function TWGS84Rectangle.LatitudeToY(const aLatitude: single): single;
begin
  Result := ReferencePointImage[rpBottomLeft][1] +
    ((aLatitude - ReferencePointWGS84[rpBottomLeft][1]) * ImageHeight / GeoHeight);
end;

function TWGS84Rectangle.LngLatToXY(const aLngLat: TVector2): TVector2;
begin
  Result := Vector2(LongtitudeToX(aLngLat[0]), LatitudeToY(aLngLat[1]));
end;

function TWGS84Rectangle.XToLongtitude(const aX: single): single;
begin
  Result := ReferencePointWGS84[rpBottomLeft][0] +
    ((aX - ReferencePointImage[rpBottomLeft][0]) * GeoWidth / ImageWidth );
end;

function TWGS84Rectangle.YToLatitude(const aY: single): single;
begin
  Result := ReferencePointWGS84[rpBottomLeft][1] +
    ((aY - ReferencePointImage[rpBottomLeft][1]) * GeoHeight / ImageHeight );
end;

function TWGS84Rectangle.XYToLngLat(const aXY: TVector2): TVector2;
begin
  Result := Vector2(XToLongtitude(aXY[0]), YToLatitude(aXY[1]));
end;

procedure TWGS84Rectangle.DefaultGeoReference;
begin
  ReferencePointWGS84[rpBottomLeft][0] := -180;
  ReferencePointWGS84[rpBottomLeft][1] := -90;
  ReferencePointWGS84[rpTopRight][0] := 180;
  ReferencePointWGS84[rpTopRight][1] := 90;
end;

function TWGS84Rectangle.CopyContainer: TWGS84Rectangle;
begin
  Result := TWGS84Rectangle.Create;
  Result.ReferencePointWGS84 := ReferencePointWGS84;
  Result.ReferencePointImage := ReferencePointImage;
end;


procedure TBaseMap.DefaultMapReference;
begin
  if MapImage = nil then
    raise Exception.Create('Error: TBaseMap.DefaultMapReference requires loaded image to work');
  ReferencePointImage[rpBottomLeft][0] := 0;
  ReferencePointImage[rpBottomLeft][1] := 0;
  ReferencePointImage[rpTopRight][0] := MapImage.Width;
  ReferencePointImage[rpTopRight][1] := MapImage.Height;
end;

constructor TBaseMap.Create(const aURL: string);
begin
  MapImage := TGLImage.Create(aURL, true);

  DefaultGeoReference;
  DefaultMapReference;
end;

destructor TBaseMap.Destroy;
begin
  FreeAndNil(MapImage);
  inherited Destroy;
end;

procedure TBaseMap.DrawCore(Container: TWGS84Rectangle);
var
  x1, y1, x2, y2: single;
begin
  //determine which part of the TBaseMap to draw into Container size
  x1 := Self.LongtitudeToX(Container.ReferencePointWGS84[rpBottomLeft][0]);
  y1 := Self.LatitudeToY(Container.ReferencePointWGS84[rpBottomLeft][1]);
  x2 := Self.LongtitudeToX(Container.ReferencePointWGS84[rpTopRight][0]);
  y2 := Self.LatitudeToY(Container.ReferencePointWGS84[rpTopRight][1]);

  MapImage.Draw(
    //draw into containter box
    Container.ReferencePointImage[rpBottomLeft][0],
    Container.ReferencePointImage[rpBottomLeft][1],
    Container.ImageWidth, Container.ImageHeight,
    //draw from MapImage
    x1, y1, x2 - x1, y2 - y1
    );
end;

procedure TBaseMap.Draw(Container: TWGS84Rectangle);
var
  c, c1, c2: TWGS84Rectangle;
begin
  { wrap the map into a cylinder - at this moment only once,
    meaning the scale of the Container should not exceed the Earth equators several times
    No wrapping of the coordinates is made }

  c := Container.CopyContainer;

  { Position container correctly }

  //move the container from the left to have a left-point larger than -180 longtitude
  while c.ReferencePointWGS84[rpBottomLeft][0] < -180 do
  begin
    c.ReferencePointWGS84[rpBottomLeft][0] := c.ReferencePointWGS84[rpBottomLeft][0] + 360;
    c.ReferencePointWGS84[rpTopRight][0] := c.ReferencePointWGS84[rpTopRight][0] + 360;
  end;
  //move the container from the right to have a right-point smaller than 180+360 longtitude
  while c.ReferencePointWGS84[rpTopRight][0] > 180 + 360 do
  begin
    c.ReferencePointWGS84[rpBottomLeft][0] := c.ReferencePointWGS84[rpBottomLeft][0] - 360;
    c.ReferencePointWGS84[rpTopRight][0] := c.ReferencePointWGS84[rpTopRight][0] - 360;
  end;

  if c.ReferencePointWGS84[rpTopRight][0] > 180 then
  begin
    //render cyllinder
    c1 := c.CopyContainer;
    c2 := c.CopyContainer;

    c1.ReferencePointImage[rpTopRight][0] := c.LongtitudeToX(180);
    c1.ReferencePointWGS84[rpTopRight][0] := 180;

    c2.ReferencePointImage[rpBottomLeft][0] := c.LongtitudeToX(180);
    c2.ReferencePointWGS84[rpBottomLeft][0] := 180;
    c2.ReferencePointImage[rpTopRight][0] := c.ReferencePointImage[rpTopRight][0] - c.ImageWidth;
    c2.ReferencePointWGS84[rpTopRight][0] := c.ReferencePointWGS84[rpTopRight][0] - 360;

    DrawCore(c1);
    DrawCore(c2);

    FreeAndNil(c1);
    FreeAndNil(c2);
  end
  else
    DrawCore(c);

  FreeAndNil(c);
end;

end.


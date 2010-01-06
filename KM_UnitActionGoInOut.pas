unit KM_UnitActionGoInOut;
interface
uses Classes, KromUtils, Math, SysUtils,
  KM_CommonTypes, KM_Defaults, KM_Houses, KM_Player, KM_Units, KM_Utils;


{This is a [fairly :P] simple action making unit go inside/outside of house}
type
  TUnitActionGoInOut = class(TUnitAction)
    private
      fStep:single;
      fHouse:TKMHouse;
      fDirection:TGoInDirection;
      fDoor:TKMPointF;
      fStreet:TKMPoint;
      fHasStarted, fWaitingForPush, fUsingDoorway, fUsedDoorway:boolean;
      procedure IncDoorway;
      procedure DecDoorway;
    public
      constructor Create(aAction: TUnitActionType; aDirection:TGoInDirection; aHouse:TKMHouse);
      constructor Load(LoadStream:TKMemoryStream); override;
      procedure SyncLoad; override;
      destructor Destroy; override;
      function ValidTileToGo(LocX, LocY:word; aUnit:TKMUnit):boolean; //using X,Y looks more clear
      procedure Execute(KMUnit: TKMUnit; out DoEnd: Boolean); override;
      procedure Save(SaveStream:TKMemoryStream); override;
    end;


implementation
uses KM_Game, KM_PlayersCollection, KM_Terrain, KM_UnitActionStay, KM_UnitActionWalkTo;


constructor TUnitActionGoInOut.Create(aAction: TUnitActionType; aDirection:TGoInDirection; aHouse:TKMHouse);
begin
  Inherited Create(aAction);
  fActionName     := uan_GoInOut;
  fHouse          := aHouse;
  fDirection      := aDirection;
  fHasStarted     := false;
  fWaitingForPush := false;
  fUsingDoorway   := true;

  if fDirection = gd_GoInside then
    fStep := 1  //go Inside (one cell up)
  else
    fStep := 0; //go Outside (one cell down)
end;


constructor TUnitActionGoInOut.Load(LoadStream:TKMemoryStream);
begin
  Inherited;
  LoadStream.Read(fStep);
  LoadStream.Read(fHouse, 4);
  LoadStream.Read(fDirection, SizeOf(fDirection));
  LoadStream.Read(fDoor, SizeOf(fDoor));
  LoadStream.Read(fStreet);
  LoadStream.Read(fHasStarted);
  LoadStream.Read(fWaitingForPush);
  LoadStream.Read(fUsingDoorway);
  LoadStream.Read(fUsedDoorway);
end;


procedure TUnitActionGoInOut.SyncLoad();
begin
  Inherited;
  fHouse := fPlayers.GetHouseByID(integer(fHouse));
end;


destructor TUnitActionGoInOut.Destroy;
begin
  if fUsedDoorway then DecDoorway;
  Inherited;
end;


procedure TUnitActionGoInOut.IncDoorway;
begin
  if fUsedDoorway then
  begin
    fLog.AssertToLog(false,'Inc doorway when already in use?');
    exit;
  end;
  inc(fHouse.DoorwayUse);
  fUsedDoorway := true;
end;


procedure TUnitActionGoInOut.DecDoorway;
begin
  if not fUsedDoorway then
  begin
    fLog.AssertToLog(false,'Dec doorway when not in use?');
    exit;
  end;
  dec(fHouse.DoorwayUse);
  fUsedDoorway := false;
end;


//Check that tile is walkable and there's no unit blocking it or that unit can be pushed away
function TUnitActionGoInOut.ValidTileToGo(LocX, LocY:word; aUnit:TKMUnit):boolean; //using X,Y looks more clear
begin
  Result := fTerrain.TileInMapCoords(LocX, LocY)
        and (fTerrain.CheckPassability(KMPoint(LocX, LocY), canWalk));
  if Result then
  Result := (fTerrain.Land[LocY,LocX].IsUnit = 0) or ((aUnit <> nil)
        and (aUnit.GetUnitAction is TUnitActionStay) and (aUnit.GetUnitActionType = ua_Walk)
        and (not TUnitActionStay(aUnit.GetUnitAction).Locked))
end;


procedure TUnitActionGoInOut.Execute(KMUnit: TKMUnit; out DoEnd: Boolean);
var Distance:single; TempUnit:TKMUnit;
begin
  DoEnd := false;

  if not fHasStarted then //Set Door and Street locations
  begin
    fUsingDoorway := true; //By default we will use the doorway rather than a diagonal entrance
    
    fDoor := KMPointF(KMUnit.GetPosition.X, KMUnit.GetPosition.Y - fStep);
    fStreet := KMPoint(KMUnit.GetPosition.X, KMUnit.GetPosition.Y + 1 - round(fStep));
    if byte(fHouse.GetHouseType) in [1..length(HouseDAT)] then
      fDoor.X := fDoor.X + (HouseDAT[byte(fHouse.GetHouseType)].EntranceOffsetXpx/4)/CELL_SIZE_PX;


    if fDirection=gd_GoInside then
    begin
      KMUnit.Direction := dir_N;  //one cell up
      KMUnit.Thought := th_None;
      KMUnit.PrevPosition := KMUnit.GetPosition;
      KMUnit.NextPosition := KMPoint(KMUnit.GetPosition.X,KMUnit.GetPosition.Y-1);
      fTerrain.UnitWalk(KMUnit.GetPosition, KMUnit.NextPosition);
      if (KMUnit.GetHome<>nil) and (KMUnit.GetHome.GetHouseType=ht_Barracks) then //Units home is barracks
        TKMHouseBarracks(KMUnit.GetHome).RecruitsInside := TKMHouseBarracks(KMUnit.GetHome).RecruitsInside + 1;
    end;

    if fDirection=gd_GoOutSide then
    begin //Attempt to find a tile bellow the door we can walk to. Otherwise we can push idle units away.
      TempUnit := fPlayers.UnitsHitTest(fStreet.X,fStreet.Y);
      if ValidTileToGo(fStreet.X,fStreet.Y,TempUnit) then
        //fStreet.X := fStreet.X
      else
      begin
        TempUnit := fPlayers.UnitsHitTest(fStreet.X-1,fStreet.Y);
        if ValidTileToGo(fStreet.X-1,fStreet.Y,TempUnit) then
        begin
          fStreet.X := fStreet.X - 1;
          fUsingDoorway := false;
        end
        else
        begin
          TempUnit := fPlayers.UnitsHitTest(fStreet.X+1,fStreet.Y);
          if ValidTileToGo(fStreet.X+1,fStreet.Y,TempUnit) then
          begin
            fStreet.X := fStreet.X + 1;
            fUsingDoorway := false;
          end
          else
            exit; //Do not exit the house if all street tiles are blocked by non-idle units, just wait
        end;
      end;

      if (TempUnit <> nil)
        and (TempUnit.GetUnitAction is TUnitActionStay) and (TempUnit.GetUnitActionType = ua_Walk)
        and (not TUnitActionStay(TempUnit.GetUnitAction).Locked) then
      begin
        TempUnit.SetActionWalk(TempUnit, fTerrain.GetOutOfTheWay(TempUnit.GetPosition,canWalk));
        TUnitActionWalkTo(TempUnit.GetUnitAction).SetPushedValues;
      end;

      if (fTerrain.Land[fStreet.Y,fStreet.X].IsUnit <> 0) then
      begin
        fWaitingForPush := true;
        fHasStarted:=true;
        exit; //Wait until my push request is dealt with before we move out
      end;

      //All checks done so unit can walk out now
      KMUnit.Direction := KMGetDirection(KMPointRound(fDoor) ,fStreet);
      KMUnit.PrevPosition := KMUnit.GetPosition;
      KMUnit.NextPosition := fStreet;
      fTerrain.UnitWalk(KMUnit.GetPosition,KMUnit.NextPosition);
      if (KMUnit.GetHome<>nil)and(KMUnit.GetHome.GetHouseType=ht_Barracks) then //Unit home is barracks
        TKMHouseBarracks(KMUnit.GetHome).RecruitsInside:=TKMHouseBarracks(KMUnit.GetHome).RecruitsInside - 1;
    end;

    if fUsingDoorway then IncDoorway;
    fHasStarted:=true;
  end;
  KMUnit.IsExchanging := (fHouse.DoorwayUse > 1);

  if fWaitingForPush then
  begin
    if (fTerrain.Land[fStreet.Y,fStreet.X].IsUnit = 0) then
    begin
      fWaitingForPush := false;
      KMUnit.Direction := KMGetDirection(KMPointRound(fDoor) ,fStreet);
      KMUnit.PrevPosition := KMUnit.GetPosition;
      KMUnit.NextPosition := fStreet;
      fTerrain.UnitWalk(KMUnit.GetPosition,KMUnit.NextPosition);
      if (KMUnit.GetHome<>nil)and(KMUnit.GetHome.GetHouseType=ht_Barracks) then //Unit home is barracks
        TKMHouseBarracks(KMUnit.GetHome).RecruitsInside:=TKMHouseBarracks(KMUnit.GetHome).RecruitsInside - 1;
    end
    else exit; //Wait until my push request is dealt with before we move out
  end;

  Distance:= ACTION_TIME_DELTA * KMUnit.GetSpeed;
  fStep := fStep - Distance * shortint(fDirection);
  KMUnit.PositionF := KMPointF(Mix(fStreet.X,fDoor.X,fStep),Mix(fStreet.Y,fDoor.Y,fStep));
  KMUnit.SetVisibility := fStep >= 0.3; //Make unit invisible when it's inside of House

  if (fStep<=0)or(fStep>=1) then
  begin
    DoEnd:=true;
    KMUnit.IsExchanging := false;
    if fUsedDoorway then DecDoorway;
    if fDirection = gd_GoInside then
      KMUnit.PositionF := fDoor
    else
      KMUnit.PositionF := KMPointF(fStreet.X,fStreet.Y);
  end
  else
    inc(KMUnit.AnimStep);
end;


procedure TUnitActionGoInOut.Save(SaveStream:TKMemoryStream);
begin
  Inherited;
  SaveStream.Write(fStep);
  if fHouse <> nil then
    SaveStream.Write(fHouse.ID) //Store ID, then substitute it with reference on SyncLoad
  else
    SaveStream.Write(Zero);
  SaveStream.Write(fDirection, SizeOf(fDirection));
  SaveStream.Write(fDoor, SizeOf(fDoor));
  SaveStream.Write(fStreet);
  SaveStream.Write(fHasStarted);
  SaveStream.Write(fWaitingForPush);
  SaveStream.Write(fUsingDoorway);
  SaveStream.Write(fUsedDoorway);
end;


end.

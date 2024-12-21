// =============================================================================
// AntiCheatEngine - (c) 2009-2016 AnthraX
// =============================================================================
// ACEAutoConfigActor:
// - An instance of this class is spawned at the start of the map
// - This actor is supposed to automatically set up the ACE UPackages list
// - Feel free to modify this package but please do share your modifications if
//   they are relevant to other people
// =============================================================================
class ACEAutoConfigActor extends IACECommon
    config(System);

// =============================================================================
// Global Variables
// =============================================================================
var Actor  PackageHelper;                 // PackageHelper reference
var string ServerActors[255];             // ServerActors list set by PackageHelper
var string ServerPackages[255];           // ServerPackages list set by PackageHelper
var string ServerMutators[255];           // Mutators list set by AutoConfig
var bool   bUsingNativeHelper;            // Is PackageHelper active? (needed for full functionality!)
var string ClassTree;                     // obj classes
var string ClassesList;                   // obj list class=class

// =============================================================================
// Config Variables
// =============================================================================
var config bool bUsePackageHelper;        // Should ACE AutoConfig use PackageHelper (evil stuff happens when set to false)
var config bool bAutoDetectWeapons;       // Auto detect weapons you're using
var config bool bAutoDetectHUDs;          // Auto detect all huds
var config bool bAutoDetectHUDExtensions; // Auto detect Nexgen HUD Extensions (they usually render stuff!)
var config bool bAutoDetectHUDMutators;   // Auto detect hud mutators
var config bool bAutoDetectScoreboards;   // Auto detect score boards
var config bool bAutoDetectPlayerTypes;   // Auto detect player types
var config bool bAutoDetectDangerousMods; // Auto detect mods that can call dangerous native functions
var config bool bAddSkinTextures;         // Automatically add skin texture files to detect skin hacks (this replaces AnthChecker)
var config bool bVerbose;                 // Log extra info into serverlog (useful for debugging)
var config string UPackages[255];         // Extra packages to add if AutoConfig doesn't find them all
var config string PackageHelperClass;

// =============================================================================
// GetItemName ~ Look for the ACE Actor and init
// =============================================================================
function string GetItemName(string Tmp)
{
    local IACEActor A;
    local Mutator M;
    local int i;

    if (Tmp ~= "CONFIG")
    {
        ACELog("AutoConfig Actor Initialized");

        foreach Level.AllActors(class 'Mutator', M)
            ServerMutators[i++] = string(M.class);

        foreach Level.AllActors(class 'IACEActor', A)
        {
            if(bUsePackageHelper)
                InitPackageHelper();

            GetPackageArrays();
            CheckConfig(A);

            break;
        }

        PackageHelper.Destroy();
        ACELog("AutoConfig Actor Exiting");
    }

    return "";
}

// =============================================================================
// ServerIsRunning ~ Checks if the specified package is in the serverpackages list
// This is no longer used! AutoConfig directly checks the PackageMap instead.
// =============================================================================
function bool ServerIsRunning(string PackageName)
{
    local int i;

    if (Right(PackageName, 2) ~= ".u")
        PackageName = Left(PackageName, Len(PackageName) - 2);

    for (i = 0; i < 255; ++i)
    {
        if (ServerPackages[i] ~= PackageName)
            return true;
    }

    if (Len(string(Level.Game.Class)) > Len(PackageName) && Left(string(Level.Game.Class), Len(PackageName)) ~= PackageName)
        return true;

    return false;
}

// =============================================================================
// ShouldBeAdded ~ Checks if the specified package should be added to the
// UPackages list. The package has to fulfill 2 conditions:
// 1) It should not be in the UPackages list yet (else it would be added twice)
// 2) It should be in the server's PackageMap. If a package is not in the
//    PackageMap, the server won't force the clients to load the package.
// =============================================================================
function bool ShouldBeAdded(IACEActor A, string PackageName)
{
    local int i;
    local string tmp;

    if (InStr(PackageName, ".") != -1)
        PackageName = Left(PackageName, InStr(PackageName, "."));

    // ACE and standard packages should never be added
    if (PackageName ~= "Core"
        || PackageName ~= "UMenu"
        || PackageName ~= "UTMenu"
        || PackageName ~= "UWindow"
        || PackageName ~= "UWeb"
        || PackageName ~= "BotPack"
        || PackageName ~= "Engine"
		|| PackageName ~= "UnrealShare"
		|| PackageName ~= "UnrealI"
		|| PackageName ~= "Fire"
        || (Left(PackageName, 4) ~= "ACEv" && Right(PackageName, 2) ~= "_C"))
        return false;

    // Packages that are already in the list should not be added
    for (i = 0; i < 255; ++i)
    {
        if (A.UPackages[i] ~= PackageName)
            return false;
    }

    // Check mastermap
    if (PackageHelper == none)
        return true;

    tmp = PackageHelper.GetItemName("ISINMAP " $ PackageName);

    if (tmp == "TRUE")
        return true;
    else
        return false;
}

// =============================================================================
// AddPackagesByClass ~ Add any packages that contain a subclass of the
// specified class. This parses the obj classes list
// =============================================================================
function AddPackagesByClass(IACEActor A, string ClassType, string FriendlyName)
{
    local string Tmp, SubClasses;
    local int index, j, k, counter, depth;

    SubClasses = "";

    if (bVerbose)
        ACELog("Checking " $ FriendlyName $ "s...");

    // Find the Superclass in the classtree
    index = InStr(ClassTree, " " $ ClassType);
    if (index != -1)
    {
        // Figure out how many spaces there are in front of the class name
        while (Mid(ClassTree, index, 1) == " ")
            index--;

        // We now know how many spaces there are in front of the class name.
        // Now we start parsing classname and we don't stop until we find a class name
        // with an equal or lesser amount of spaces before it than the classtype itself.
        // Any class we encounter before we stop parsing is a subclass of the classtype.
        Tmp   = Mid(ClassTree, index + 1);
        depth = InStr(Tmp, ClassType);

        // Counter = amount of spaces before the current class name
        for (j = Len(ClassType)+depth; j < Len(Tmp); ++j)
        {
            if (Mid(Tmp, j, 1) == " ")
                counter++;
            else
            {
                if (counter > depth)
                {
                    k          = InStr(Mid(Tmp, j+1), " ");
                    SubClasses = SubClasses $ Left(Mid(Tmp, j), k+1)$",";
                    counter    = 0;
                    j         += k;
                }
                else
                    break;
            }
        }
    }

    // All subclasses of the specified classtype are now inside the SubClasses string
    // We now have to figre out which packages these subclasses reside in and if these packages
    // are in the PackageMap. If they are in the packagemap then they are relevant to the players
    // and they should be added to the ACE UPackages list
    k = xxGetTokenCount(SubClasses, ",")-1;
    for (j = 0; j < k; j++)
    {
        index = InStr(ClassesList, "." $ xxGetToken(SubClasses, ",", j) $ " ");
        if (index != -1)
        {
            Tmp   = Left(ClassesList, index);
            index = Len(Tmp) - 1;

            while (Mid(Tmp, index, 1) != " ")
                index--;
            Tmp = Right(Tmp, Len(Tmp) - index - 1);

            if (bVerbose)
                ACELog("Found " $ FriendlyName $ ": " $ Tmp $ "." $ xxGetToken(SubClasses, ",", j));

            // Found one!
            if (ShouldBeAdded(A, Tmp))
            {
                ACELog("Found a new package containing a " $ FriendlyName $ ": " $ Tmp);
                AddPackage(A, Tmp);
            }
        }
    }
}

// =============================================================================
// CheckConfig ~
// =============================================================================
function CheckConfig(IACEActor A)
{
    local int i,j,TmpPackagesCnt;
    local string Tmp,Tmp2,Pkgs;
	local string TmpPackages[255];

    if (bVerbose)
        ACELog("Cleaning up packageslist...");

    for (i = 0; i < 255; ++i)
	{
		// If a package that was previously added is still in the UEngine PackageMap, 
		// then keep it in our UPackages list across map switches
		Tmp = A.UPackages[i];
		if (InStr(Tmp, ".") != -1)
			Tmp = Left(Tmp, InStr(Tmp, "."));		

		if (Len(Tmp) > 0)
		{
			Tmp2 = PackageHelper.GetItemName("ISINMAP " $ Tmp);
			if (Tmp2 == "TRUE")
			{
				TmpPackages[TmpPackagesCnt++] = Tmp;
			}
		}
		
        A.UPackages[i] = "";
	}
	
	for (i = 0; i < TmpPackagesCnt; ++i)
	{
		if (bVerbose)
			ACELog("Keeping UPackage from previous map: " $ TmpPackages[i]);
		AddPackage(A, TmpPackages[i]);
	}

    // Some maps have embedded code for extra effects and such
    Tmp = string(Level);
    if (InStr(Tmp, ".") != -1)
        Tmp = Left(Tmp, InStr(Tmp, "."));
    if (PackageHelper != none && PackageHelper.GetItemName("HASEMBEDDEDCODE " $ Tmp) == "TRUE")
    {
        ACELog("Mapfile has embedded code");
        ACELog("AutoConfig Added Package:"@Tmp);
        AddPackage(A, Tmp);
    }

    if (bVerbose)
        ACELog("Checking gametype: " $ string(Level.Game.Class));

    // Check if gametype is there
    if (Left(Caps(string(Level.Game.Class)), 7) != "BOTPACK")
        AddPackage(A, Left(string(Level.Game.class), InStr(string(Level.Game.class), ".")));

    // Cache classes list
    if (bAutoDetectWeapons || bAutoDetectHUDs || bAutoDetectHUDMutators || bAutoDetectScoreboards)
    {
        ClassesList = Level.ConsoleCommand("obj list class=class");
        ClassTree   = Level.ConsoleCommand("obj classes")$" ";

		if (bVerbose)
		{
			ACELog("ClassesList: " $ ClassesList);
			ACELog("ClassTree: " $ ClassTree);
		}
    }

    // weapons
    if (bAutoDetectWeapons)
        AddPackagesByClass(A, "TournamentWeapon", "Weapon");

    // huds
    if (bAutoDetectHUDs)
        AddPackagesByClass(A, "ChallengeHUD", "HUD");

    // Nexgen hud extensions. These hud extensions are subclasses of
    // NexgenHUDExtension but not of ChallengeHUD.
    if (bAutoDetectHUDExtensions)
        AddPackagesByClass(A, "NexgenHUDExtension", "Nexgen HUD Extension");

    // Add playerpawn classes
    if (bAutoDetectPlayerTypes)
        AddPackagesByClass(A, "PlayerPawn", "Player Type");

    // These are tricky to detect since there is no HUDMutator class.
    // All HUDMutators are just mutators but not all mutators are hudmutators.
    // Using some super lame trick to detect these...
    if (bAutoDetectHUDMutators)
    {
        // Check for running hudmutators
        if (bVerbose)
            ACELog("Checking HUDMutators...");

        if (PackageHelper != none)
        {
            Pkgs = PackageHelper.GetItemName("FINDIMPORTS ENGINE.MUTATOR.POSTRENDER");

            while (InStr(Pkgs, ";") != -1)
            {
                Tmp2 = Left(Pkgs, InStr(Pkgs, ";"));
                Pkgs = Mid(Pkgs, InStr(Pkgs, ";") + 1);

                if (ShouldBeAdded(A, Tmp2))
                {
                    ACELog("Found a new package containing a HUDMutator: " $ Tmp2);
                    AddPackage(A, Tmp2);
                }
            }
        }
    }

    // Scoreboards render quite a lot!
    if (bAutoDetectScoreboards)
        AddPackagesByClass(A, "ScoreBoard", "Scoreboard");

    // Add known packages if they are in the PackageMap
    if (PackageHelper != none)
    {
        // AnthChecker replacement
        if (bAddSkinTextures)
        {
            if (PackageHelper.GetItemName("ISINMAP COMMANDOSKINS") == "TRUE")
                AddPackage(A, "commandoskins.utx");
            if (PackageHelper.GetItemName("ISINMAP FCOMMANDOSKINS") == "TRUE")
                AddPackage(A, "FCommandoSkins.utx");
            if (PackageHelper.GetItemName("ISINMAP FEMALE1SKINS") == "TRUE")
                AddPackage(A, "Female1Skins.utx");
            if (PackageHelper.GetItemName("ISINMAP FEMALE2SKINS") == "TRUE")
                AddPackage(A, "Female2Skins.utx");
            if (PackageHelper.GetItemName("ISINMAP SGIRLSKINS") == "TRUE")
                AddPackage(A, "SGirlSkins.utx");
            if (PackageHelper.GetItemName("ISINMAP SOLDIERSKINS") == "TRUE")
                AddPackage(A, "Soldierskins.utx");
            if (PackageHelper.GetItemName("ISINMAP BOSSSKINS") == "TRUE")
                AddPackage(A, "BossSkins.utx");
        }
    }

    // Finally process the UPackages that were manually added by the user
    for (i = 0; i < 255; ++i)
    {
        Tmp = UPackages[i];
        if (InStr(Tmp, ".") != -1)
            Tmp = Left(Tmp, InStr(Tmp, "."));

        if (UPackages[i] != "" &&
           PackageHelper != none &&
           PackageHelper.GetItemName("ISINMAP "$Tmp) == "TRUE")
            AddPackage(A, UPackages[i]);
    }

	// This is super slow so we want to do this last
	if (bAutoDetectDangerousMods && PackageHelper != none)
	{
		// build the exclusion list
		Tmp = "Core;Engine;UMenu;UTMenu;UWindow;Botpack;UWeb;UnrealI;UnrealShare;Fire;";

		for (i = 0; i < 255; ++i)
			if (UPackages[i] != "")
			   Tmp = Tmp $ UPackages[i] $ ";";

		// now scan all remaining packages to see if any of them could
		// potentially call one of the native functions ACE considers
		// dangerous (because a lot of cheats use them)

		// Current list of dangerous natives:
		// 277: AActor::execTrace
		// 299: AActor::execSetRotation
		// 309: AActor::execTraceActors
		// 311: AActor::execVisibleActors
		// 312: AActor::execVisibleCollidingActors
		// 465: UCanvas::execDrawText
		// 466: UCanvas::execDrawTile
		// 467: UCanvas::execDrawActor
		// 468: UCanvas::execDrawTileClipped
		// 469: UCanvas::execDrawTextClipped
		// 471: UCanvas::execDrawClippedActor
		// 472: UScriptedTexture::execDrawText
		// 473: UScriptedTexture::execDrawTile
		// 474: UScriptedTexture::execDrawColoredText
		// 548: AActor::execFastTrace

		Pkgs = PackageHelper.GetItemName("FINDNATIVECALLS 277;299;309;311;312;465;466;467;468;469;471;472;473;474;548; " $ Tmp);
        while (InStr(Pkgs, ";") != -1)
        {
            Tmp2 = Left(Pkgs, InStr(Pkgs, ";"));
            Pkgs = Mid(Pkgs, InStr(Pkgs, ";") + 1);

            if (ShouldBeAdded(A, Tmp2))
            {
                ACELog("Found a new package containing a dangerous function call: " $ Tmp2);
                AddPackage(A, Tmp2);
            }
        }
	}

    // Other settings!
    for (i = 0; i < 255; ++i)
    {
        if (A.bAllowCrosshairScaling)
        {
            if (InStr(CAPS(A.UPackages[i]), "LEAGUEAS") != -1)
            {
                ACELog("Crosshair Scaling Disabled (LEAGUEAS)");
                A.bAllowCrosshairScaling = false;
            }
            else if (Left(CAPS(A.UPackages[i]), 3) == "EUT")
            {
                ACELog("Crosshair Scaling Disabled (EUT)");
                A.bAllowCrosshairScaling = false;
            }
        }
    }
}

// =============================================================================
// RemovePackage
// =============================================================================
function RemovePackage(IACEActor A, int i)
{
    local int j;

    ACELog("AutoConfig Removed Package:"@A.UPackages[i]);
    A.UPackages[i] = "";

    for (j = i; j < 254; ++j)
    {
        if (A.UPackages[j+1] != "")
        {
            A.UPackages[j] = A.UPackages[j+1];
            A.UPackages[j+1] = "";
        }
    }
}

// =============================================================================
// AddPackage
// =============================================================================
function AddPackage(IACEActor A, string PackageName)
{
    local int i;

    if (InStr(PackageName, ".") != -1)
        PackageName = Left(PackageName, InStr(PackageName, "."));

    for (i = 0; i < 255; ++i)
    {
        if (A.UPackages[i] ~= PackageName)
            return;
    }

    for (i = 0; i < 255; ++i)
    {
        if (A.UPackages[i] == "")
        {
            A.UPackages[i] = PackageName;
            ACELog("AutoConfig Added Package:"@PackageName);
            return;
        }
    }

    ACELog("ERROR: AutoConfig Couldn't add package:"@PackageName@"- ACE Package Array is full!");
}

// =============================================================================
// InitPackageHelper ~
// =============================================================================
function InitPackageHelper()
{
    local class<Actor> PackageHelperCls;

    PackageHelperCls = class<Actor>(DynamicLoadObject(PackageHelperClass,class'class',true));
    if (PackageHelperCls != none)
    {
        PackageHelper = Level.Spawn(PackageHelperCls);
        if (PackageHelper != none)
        {
            PackageHelper.Touch(self);
            bUsingNativeHelper = true;
        }
        else
        {
            ACELog("ERROR: "$"PackageHelper failed to spawn!");
        }
    }
    else
    {
        ACELog("ERROR: "$"Failed to resolve PackageHelper class!");
    }
}

// =============================================================================
// GetPackageArrays ~ Get the ServerActors/ServerPackages list
// =============================================================================
function GetPackageArrays()
{
    local string zzServerPackages, zzServerActors, zzToken;
    local int zzI;

    // Wipe the arrays
    for (zzI = 0; zzI < 255; ++zzI)
    {
        ServerActors[zzI] = "";
        ServerPackages[zzI] = "";
    }

    // Fill the arrays
    if (!bUsingNativeHelper)
    {
        // Retrieve the list from the console and parse
        zzServerActors = ConsoleCommand("get Engine.GameEngine ServerActors");
        zzServerPackages = ConsoleCommand("get Engine.GameEngine ServerPackages");

        if (Right(zzServerActors,2) ~= "\")")
            zzServerActors = Left(zzServerActors,Len(zzServerActors)-2);
        if (Left(zzServerActors,2) ~= "(\"")
            zzServerActors = Mid(zzServerActors,2);

        if (Right(zzServerPackages,2) ~= "\")")
            zzServerPackages = Left(zzServerPackages,Len(zzServerPackages)-2);
        if (Left(zzServerPackages,2) ~= "(\"")
            zzServerPackages = Mid(zzServerPackages,2);

        for (zzI = 0; zzI < 255; ++zzI)
        {
            zzToken = xxGetToken(zzServerActors,"\",\"",zzI);
            if (zzToken != "")
                ServerActors[zzI] = zzToken;
            else
                break;
        }

        for (zzI = 0; zzI < 255; ++zzI)
        {
            zzToken = xxGetToken(zzServerPackages,"\",\"",zzI);
            if (zzToken != "")
                ServerPackages[zzI] = zzToken;
            else
                break;
        }
    }
    else
    {
        PackageHelper.GetItemName("GETPACKAGEINFO");
    }
}

// =============================================================================
// RestartMap ~ Reboot the server
// =============================================================================
function RestartMap()
{
    Level.ServerTravel(Left(Mid(Level.GetLocalURL(),InStr(Level.GetLocalURL(),"/")+1),InStr(Mid(Level.GetLocalURL(),InStr(Level.GetLocalURL(),"/")+1),"?")),false);
}

// =============================================================================
// Defaultproperties
// =============================================================================
defaultproperties
{
    bUsePackageHelper=true
    bAutoDetectWeapons=true
    bAutoDetectHUDs=true
    bAutoDetectHUDExtensions=true
    bAutoDetectHUDMutators=true
    bAutoDetectScoreboards=true
    bAutoDetectPlayerTypes=true
	bAutoDetectDangerousMods=true
    bAddSkinTextures=true	
    bVerbose=false
	PackageHelperClass="PackageHelper_v15.PHActor"
}
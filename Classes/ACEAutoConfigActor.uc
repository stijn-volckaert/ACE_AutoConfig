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
var config bool bAddSkinTextures;         // Automatically add skin texture files to detect skin hacks (this replaces AnthChecker)
var config bool bVerbose;                 // Log extra info into serverlog (useful for debugging)
var config string UPackages[32];          // Extra packages to add if AutoConfig doesn't find them all

const IACEUPackagesSize = 256;             // The size of the IACEActor.UPackages array.

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

    for (i = 0; i < arrayCount(ServerPackages); ++i)
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

    if (!(Right(PackageName, 2) ~= ".u"))
        PackageName = PackageName $ ".u";

    // ACE and standard packages should never be added
    if (PackageName ~= "Core.u"
        || PackageName ~= "UMenu.u"
        || PackageName ~= "UTMenu.u"
        || PackageName ~= "UWindow.u"
        || PackageName ~= "UWeb.u"
        || PackageName ~= "BotPack.u"
        || PackageName ~= "Engine.u"
        || (Left(PackageName, 4) ~= "ACEv" && Right(PackageName, 4) ~= "_C.u"))
        return false;

    // Packages that are already in the list should not be added
    for (i = 0; i < IACEUPackagesSize; ++i)
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
        index = InStr(ClassesList, "." $ xxGetToken(SubClasses, ",", j));
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
                AddPackage(A, Tmp $ ".u");
            }
        }
    }
}

// =============================================================================
// CheckConfig ~
// =============================================================================
function CheckConfig(IACEActor A)
{
    local int i,j;
    local string Tmp,Tmp2;

    if (bVerbose)
        ACELog("Cleaning up packageslist...");

    for (i = 0; i < IACEUPackagesSize; ++i)
        A.UPackages[i] = "";

    // Some maps have embedded code for extra effects and such
    Tmp = string(Level);
    if (InStr(Tmp, ".") != -1)
        Tmp = Left(Tmp, InStr(Tmp, "."));
    if (PackageHelper != none && PackageHelper.GetItemName("HASEMBEDDEDCODE " $ Tmp) == "TRUE")
    {
        ACELog("Mapfile has embedded code");
        ACELog("AutoConfig Added Package:"@Tmp$".unr");
        A.UPackages[0] = Tmp $ ".unr";
    }

    if (bVerbose)
        ACELog("Checking gametype: " $ string(Level.Game.Class));

    // Check if gametype is there
    if (Left(Caps(string(Level.Game.Class)), 7) != "BOTPACK")
        AddPackage(A, Left(string(Level.Game.class), InStr(string(Level.Game.class), ".")) $ ".u");

    // Cache classes list
    if (bAutoDetectWeapons || bAutoDetectHUDs || bAutoDetectHUDMutators || bAutoDetectScoreboards)
    {
        ClassesList = Level.ConsoleCommand("obj list class=class");
        ClassTree   = Level.ConsoleCommand("obj classes")$" ";
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

    // These are tricky to detect since there is no HUDMutator class.
    // All HUDMutators are just mutators but not all mutators are hudmutators.
    // Using some super lame trick to detect these...
    if (bAutoDetectHUDMutators)
    {
        // Check for running hudmutators
        if (bVerbose)
            ACELog("Checking HUDMutators...");
        Tmp = Level.ConsoleCommand("obj refs class=function name=engine.mutator.postrender");
        i   = InStr(Tmp, "Shortest reachability");
        if (i != -1)
            Tmp = Left(Tmp, i);
        i = 0;
        while (i != -1)
        {
            i = InStr(Tmp, "Function ");
            if (i != -1)
            {
                Tmp = Mid(Tmp, i + 9);
                j   = InStr(Tmp, ".");
                if (j != -1)
                {
                    Tmp2 = Left(Tmp, j);
                    if (ShouldBeAdded(A, Tmp2))
                    {
                        ACELog("Found a new package containing a HUDMutator: " $ Tmp2);
                        AddPackage(A, Tmp2 $ ".u");
                    }
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
        if (PackageHelper.GetItemName("ISINMAP UNREALSHARE") == "TRUE")
            AddPackage(A, "Unrealshare.u");
        if (PackageHelper.GetItemName("ISINMAP UNREALI") == "TRUE")
            AddPackage(A, "UnrealI.u");
        if (PackageHelper.GetItemName("ISINMAP FIRE") == "TRUE")
            AddPackage(A, "Fire.u");

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
    for (i = 0; i < arrayCount(UPackages); ++i)
    {
        Tmp = UPackages[i];
        if (InStr(Tmp, ".") != -1)
            Tmp = Left(Tmp, InStr(Tmp, "."));

        if (UPackages[i] != "" &&
           PackageHelper != none &&
           PackageHelper.GetItemName("ISINMAP "$Tmp) == "TRUE")
            AddPackage(A, UPackages[i]);
    }

    // Other settings!
    for (i = 0; i < IACEUPackagesSize; ++i)
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

    for (j = i; j < IACEUPackagesSize - 1; ++j)
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

    if (!(Right(PackageName, 2) ~= ".u") &&
        !(Right(PackageName, 4) ~= ".utx") &&
        !(Right(PackageName, 4) ~= ".umx") &&
        !(Right(PackageName, 4) ~= ".uax") &&
        !(Right(PackageName, 4) ~= ".unr"))
        PackageName = PackageName $ ".u";

    for (i = 0; i < IACEUPackagesSize; ++i)
    {
        if (A.UPackages[i] ~= PackageName)
            return;
    }

    for (i = 0; i < IACEUPackagesSize; ++i)
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
    local class<Actor> PackageHelperClass;

    PackageHelperClass = class<Actor>(DynamicLoadObject("PackageHelper_v13.PHActor",class'class',true));
    if (PackageHelperClass != none)
    {
        PackageHelper = Level.Spawn(PackageHelperClass);
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
    for (zzI = 0; zzI < arrayCount(ServerActors); ++zzI)
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

        for (zzI = 0; zzI < arrayCount(ServerActors); ++zzI)
        {
            zzToken = xxGetToken(zzServerActors,"\",\"",zzI);
            if (zzToken != "")
                ServerActors[zzI] = zzToken;
            else
                break;
        }

        for (zzI = 0; zzI < arrayCount(ServerPackages); ++zzI)
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
    bAddSkinTextures=true
    bVerbose=false
}

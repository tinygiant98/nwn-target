// -----------------------------------------------------------------------------
//    File: util_i_target.nss
//  System: Target Hook System
// -----------------------------------------------------------------------------
// Description:
//  Primary functions for PW Subsystem
// -----------------------------------------------------------------------------
// Builder Use:
//  None!  Leave me alone.
// -----------------------------------------------------------------------------
// Changelog:
//
// 20200208:
//      Initial Release

/*
Note: util_i_chat will not function without other utility includes from squattingmonk's
sm-utils.  These utilities can be obtained from
https://github.com/squattingmonk/nwn-core-framework/tree/master/src/utils.

Specifically, util_i_varlists, util_i_debug, util_i_color and util_i_math are
required.

This system is designed to take advantage of NWN:EE's ability to forcibly enter
Targeting Mode for any given PC.  It is designed to add a single-use, multi-use,
or unlimite-use hook to the specified PC.  Once the PC has satisfied the conditions
of the hook, or manually exited targeting mode, the targeted objects/locations
will be saved and a specified script will be run.

Setup:

1.  You must attach a targeting event script to the module.  For example, in your
module load script, you can add this line:

    SetEventScript(GetModule(), EVENT_SCRIPT_MODULE_ON_PLAYER_TARGET, "module_opt");

where "module_opt" is the script that will handle all forced targeting.

2.  The chosen script ("module_opt") must contain reference to the util_i_target
function SatisfyTargetingHook().  An example of this follows.

#include util_i_target

void main()
{
    object oPC = GetLastPlayerToSelectTarget();

    int nHookID = GetLocalInt(oPC, TARGET_HOOK_ID);
    if (nHookID)
        SatisfyTargetingHook(oPC, nHookID);
}

Usage:

The design of this system center around a module-wide list of "Targeting Hooks"
that are accessed by util_i_target when a player targets any object or
manually exits targeting mode.

Here is the prototype for the AddTargetingHook() function:

int AddTargetingHook(object oPC, string sVarName, int nObjectType = OBJECT_TYPE_ALL, string sScript = "", int nUses = 1);

oPC is the PC object that will be associated with this hook.  This PC will be the
    player that will be entered into Targeting Mode.  Additionally, the results of
    his targeting will be saved to the PC object.
sVarName is the variable name to save the results of targeting to.  This allows
    for targeting hooks to be added that can be saved to different variable for
    several purposes.
nObjectType is the limiting variable for the types of objects the PC can target
    when they are in targeting mode forced by this hook.  It is an optional
    parameter and can be bitmasked with any visible OBJECT_TYPE_* constant.
sScript is the resref of the script that will run once the targeting conditions
    have been satisfied.  For example, if you create a multi-use targeting hook,
    this script will run after all uses have been exhausted.  This script will
    also run if the player manually exits targeting mode without selecting a
    target.  Optional.  A script-run is not always desirable.  The targeted object
    may be required for later use, so a script entry is not a requirement.
nUses is the number of times this target hook can be used before it is deleted.
    This is designed to allow multiple targets to be selected and saved to the
    same variable name sVarName.  Multi-selection could be useful for DMs in
    defining DM Experience members, even from different parties, or selecting
    multiple NPCs to accomplish a specific action.  Optional, defaulted to 1.

    Note:  Targeting mode uses specified by nUses will be decremented every time
        a player selects a target.  Uses will also be decremented when a user
        manually exits targeting mode.  Manually exiting targeting mode will
        delete the targeting hook, but any selected targets before exiting
        targeting mode will be saved to the specified variable.

To add a single-use targeting hook that enters the PC into targeting mode, allows
    for the selection of a single placeable | creature, then runs the script
    "temp_target" upon exiting target mode or selecting a single target:

    int nObjectType = OBJECT_TYPE_PLACEABLE | OBJECT_TYPE_CREATURE;
    AddTargetingHook(oPC, "spell_target", nObjectType, "temp_target");

To add a multi-use targeting hook that enters the PC into targeting mode, allows
    for the selection of a specified number of placeables | creatures, then runs
    the script "temp_target" upon exiting targeting mode or selecting the
    specified number of targets:

    int nObjectType = OBJECT_TYPE_PLACEABLE | OBJECT_TYPE_CREATURE;
    AddTargetingHook(oPC, "DM_Party", nObjectType, "temp_target", 3);

    Note:  In this case, the player can select up to three targets to save to
        the "DM_Party" variable.

To add an unlmited-use targeting hook that enters the PC into targeting mode, allows
    for the selection of an unspecified number of creatures, then runs
    the script "temp_target" upon exiting targeting mode or selection of an invalid
    target:

    int nObjectType = OBJECT_TYPE_CREATURE;
    AddTargetingHook(oPC, "NPC_Townspeople", nObjectType, "temp_target", -1);

Here is an example "temp_target" post-targeting script that will access each of the
    targets saved to the specified variable and send their data to the chat log:

#include "util_i_target"
#include "util_i_variable"

void main()
{
    object oPC = OBJECT_SELF;
    int n, nCount = CountTargetingHookTargets(oPC, TARGET_HOOK_VARNAME);

    Notice("Targeting process complete: " + IntToString(nCount) + " target" + (nCount == 1 ? "" : "s") + " saved");

    for (n = 0; n < nCount; n++)
    {
        object oTarget = GetTargetingHookObject(oPC, TARGET_HOOK_VARNAME, n);
        location lTarget = GetTargetingHookLocation(oPC, TARGET_HOOK_VARNAME, n);
        vector vTarget = GetTargetingHookPosition(oPC, TARGET_HOOK_VARNAME, n);

        Notice("  Target #" + IntToString(n) +
               "\n    Target Tag -> " + (GetIsPC(oTarget) ? GetName(oTarget) : GetTag(oTarget)) +
               "\n    Target Location -> " + __LocationToString(lTarget) +
               "\n    Target Position -> (" + FloatToString(vTarget.x, 3, 1) + ", " +
                                              FloatToString(vTarget.y, 3, 1) + ", " +
                                              FloatToString(vTarget.z, 3, 1) + ")");
    }
}

Note: Target objects and positions saved to the variables are persistent while the server
is running, but are not persistent (though they can be made so).  If you wish to overwrite
a set of target data with a variable you've already used, ensure you first delete the
current target data with the function DeleteTargetingHookTargets();
*/

// -----------------------------------------------------------------------------
//                              Configuration
// -----------------------------------------------------------------------------

// There are no configuration values available for this system

// -----------------------------------------------------------------------------
//                      LEAVE EVERYTHING BELOW HERE ALONE!
// -----------------------------------------------------------------------------

#include "util_i_debug"
#include "util_i_varlists"
#include "util_i_variable"

object oModule = GetModule();

// VarList names for the global targeting hook lists
const string TARGET_HOOK_ID = "TARGET_HOOK_ID";
const string TARGET_HOOK_VARNAME = "TARGET_HOOK_VARNAME";
const string TARGET_HOOK_OBJECT_TYPE = "TARGET_HOOK_OBJECT_TYPE";
const string TARGET_HOOK_USES = "TARGET_HOOK_USES";
const string TARGET_HOOK_SCRIPT = "TARGET_HOOK_SCRIPT";

// Variable names for 
const string TARGET_HOOK_OBJECT = "TARGET_HOOK_OBJECT";
const string TARGET_HOOK_POSITION = "TARGET_HOOK_POSITION";

// -----------------------------------------------------------------------------
//                              Function Prototypes
// -----------------------------------------------------------------------------

// ---< GetTargetingHook[Index|VarName|ObjectType|Uses] >---
// Returns a targeting hook property from the targeting hook associated with
// nHookID from the global properties list.
int GetTargetingHookIndex(int nHookID);
string GetTargetingHookVarName(int nHookID);
int GetTargetingHookObjectType(int nHookID);
int GetTargetingHookUses(int nHookID);
string GetTargetingHookScript(int nHookID);

// ---< AddTargetingHook >---
// Adds a targeting hook to the global targeting hook list and saves the desired
// variable name sVarName and number of uses remaining nUses.
int AddTargetingHook(object oPC, string sVarName, int nObjectType = OBJECT_TYPE_ALL, string sScript = "", int nUses = 1);

// ---< DeleteTargetingHook >---
// Removes a targeting hook from the global targeting hook list.  Called automatically
// when the number of remaining uses decrements to 0.
void DeleteTargetingHook(object oPC, int nHookID);

// ---< SatisfyTargetingHook >---
// Saves the targeting data to the PC object as an object and location variable
// defined by sVarName in AddTargetingHook.  Decrements remaining hook uses and,
// if required, deletes the targeting hook.
void SatisfyTargetingHook(object oPC, int nHookID);

// ---< GetTargetingHook[Object|Location|Position] >---
// Returns the saved value from oPC associated with sVarName.
object GetTargetingHookObject(object oPC, string sVarName, int nIndex = 0);
location GetTargetingHookLocation(object oPC, string sVarName, int nIndex = 0);
vector GetTargetingHookPosition(object oPC, string sVarName, int nIndex = 0);

// ---< CountTargetingHookTargets >---
// Returns the number of targets associated with the target saved as sVarName on
// oPC.  This will normally be one except in the case of a multi-use hook.
int CountTargetingHookTargets(object oPC, string sVarName);

// ---< DeleteTargetingHookTarget[s] >---
// Removes the target data saved on oPC under sVarName at nIndex.  For a single
// target, the remaining count will be returns.  For multiple targets, there is
// no return value.
int DeleteTargetingHookTarget(object oPC, string sVarName, int nIndex = 0);
void DeleteTargetingHookTargets(object oPC, string sVarName);

// -----------------------------------------------------------------------------
//                            Private Function Definitions
// -----------------------------------------------------------------------------

// Reduces the number of targeting hooks remaining.  When the remaining number is
// 0, the hook is automatically deleted.
int DecrementTargetingHookUses(object oPC, int nHookID)
{
    int nUses = GetTargetingHookUses(nHookID);
    
    if (!--nUses)
    {
        Notice("Decrementing target hook uses for ID " + HexColorString(IntToString(nHookID), COLOR_CYAN) +
               "\n  Uses remaining -> " + (nUses ? HexColorString(IntToString(nUses), COLOR_CYAN) : HexColorString(IntToString(nUses), COLOR_RED_LIGHT)) + "\n");
        DeleteTargetingHook(oPC, nHookID);
    }
    else
    {
        SetListInt(oModule, GetTargetingHookIndex(nHookID), nUses, TARGET_HOOK_USES);
        EnterTargetingMode(oPC, GetTargetingHookObjectType(nHookID));
    }

    return nUses;
}

// -----------------------------------------------------------------------------
//                            Public Function Definitions
// -----------------------------------------------------------------------------

// Temporary function for feedback purposes only
string ObjectTypeToString(int nObjectType)
{
    string sResult;

    if (nObjectType & OBJECT_TYPE_CREATURE)
        sResult += (sResult == "" ? "" : ", ") + "Creatures";

    if (nObjectType & OBJECT_TYPE_ITEM)
        sResult += (sResult == "" ? "" : ", ") + "Items";
    
    if (nObjectType & OBJECT_TYPE_TRIGGER)
        sResult += (sResult == "" ? "" : ", ") + "Triggers";

    if (nObjectType & OBJECT_TYPE_DOOR)
        sResult += (sResult == "" ? "" : ", ") + "Doors";

    if (nObjectType & OBJECT_TYPE_AREA_OF_EFFECT)
        sResult += (sResult == "" ? "" : ", ") + "Areas of Effect";

    if (nObjectType & OBJECT_TYPE_WAYPOINT)
        sResult += (sResult == "" ? "" : ", ") + "Waypoints";

    if (nObjectType & OBJECT_TYPE_PLACEABLE)
        sResult += (sResult == "" ? "" : ", ") + "Placeables";

    if (nObjectType & OBJECT_TYPE_STORE)
        sResult += (sResult == "" ? "" : ", ") + "Stores";

    if (nObjectType & OBJECT_TYPE_ENCOUNTER)
        sResult += (sResult == "" ? "" : ", ") + "Encounters";

    if (nObjectType & OBJECT_TYPE_TILE)
        sResult += (sResult == "" ? "" : ", ") + "Tiles";

    return sResult;
}

int GetTargetingHookIndex(int nHookID)
{
    return FindListInt(oModule, nHookID, TARGET_HOOK_ID);
}

string GetTargetingHookVarName(int nHookID)
{
    return GetListString(oModule, GetTargetingHookIndex(nHookID), TARGET_HOOK_VARNAME);
}

int GetTargetingHookObjectType(int nHookID)
{
    return GetListInt(oModule, GetTargetingHookIndex(nHookID), TARGET_HOOK_OBJECT_TYPE);
}

int GetTargetingHookUses(int nHookID)
{
    return GetListInt(oModule, GetTargetingHookIndex(nHookID), TARGET_HOOK_USES);
}

string GetTargetingHookScript(int nHookID)
{
    return GetListString(oModule, GetTargetingHookIndex(nHookID), TARGET_HOOK_SCRIPT);
}

int AddTargetingHook(object oPC, string sVarName, int nObjectType = OBJECT_TYPE_ALL, string sScript = "", int nUses = 1)
{
    int nHookID;

    do
    {
        nHookID = Random (20000) + 1;
    } while (FindListInt(oModule, nHookID, TARGET_HOOK_ID) != -1);

    Notice("Adding targeting hook ID " + HexColorString(IntToString(nHookID), COLOR_CYAN) +
           "\n  sVarName -> " + HexColorString(sVarName, COLOR_CYAN) +
           "\n  nObjectType -> " + HexColorString(ObjectTypeToString(nObjectType), COLOR_CYAN) +
           "\n  sScript -> " + (sScript == "" ? HexColorString("[None]", COLOR_RED_LIGHT) : HexColorString(sScript, COLOR_CYAN)) +
           "\n  nUses -> " + (nUses == -1 ? HexColorString("Unlimited", COLOR_CYAN) : (nUses > 0 ? HexColorString(IntToString(nUses), COLOR_CYAN) : HexColorString(IntToString(nUses), COLOR_RED_LIGHT))) + "\n");

    AddListInt(oModule, nHookID, TARGET_HOOK_ID);
    AddListString(oModule, sVarName, TARGET_HOOK_VARNAME);
    AddListInt(oModule, nObjectType, TARGET_HOOK_OBJECT_TYPE);
    AddListInt(oModule, nUses, TARGET_HOOK_USES);
    AddListString(oModule, sScript, TARGET_HOOK_SCRIPT);

    SetLocalInt(oPC, TARGET_HOOK_ID, nHookID);
    return nHookID;
}

void DeleteTargetingHook(object oPC, int nHookID)
{
    int nIndex = GetTargetingHookIndex(nHookID);
    string sScript;;
    
    if (nIndex != -1)
    {
        sScript = GetTargetingHookScript(nHookID);

        Notice("Deleting targeting hook ID " + HexColorString(IntToString(nHookID), COLOR_CYAN) + "\n");

        DeleteListInt(oModule, nIndex, TARGET_HOOK_ID);
        DeleteListString(oModule, nIndex, TARGET_HOOK_VARNAME);
        DeleteListInt(oModule, nIndex, TARGET_HOOK_OBJECT_TYPE);
        DeleteListInt(oModule, nIndex, TARGET_HOOK_USES);
        DeleteListString(oModule, nIndex, TARGET_HOOK_SCRIPT);

        DeleteLocalInt(oPC, TARGET_HOOK_ID);

        if (sScript != "")
        {
            Notice("Running post-targeting script " + sScript);
            ExecuteScript(sScript, oPC);
        }
        else
            Notice("No post-targeting script specified");
    }
    else
        Notice("Targeting hook deletion failed; hook could not be found.");
}

void SatisfyTargetingHook(object oPC, int nHookID)
{
    string sVarName = GetTargetingHookVarName(nHookID);
    object oTarget = GetTargetingModeSelectedObject();
    vector vTarget = GetTargetingModeSelectedPosition();

    int nValid = TRUE;

    Notice("Targeted Object -> " + (GetIsObjectValid(oTarget) ? (GetIsPC(oTarget) ? HexColorString(GetName(oTarget), COLOR_GREEN_LIGHT) : HexColorString(GetTag(oTarget), COLOR_CYAN)) : HexColorString("OBJECT_INVALID", COLOR_RED_LIGHT)) +
           "\n  Type -> " + HexColorString(ObjectTypeToString(GetObjectType(oTarget)), COLOR_CYAN));
    Notice("Targeted Position -> " + (vTarget == Vector() ? HexColorString("POSITION_INVALID", COLOR_RED_LIGHT) :
                                    HexColorString("(" +FloatToString(vTarget.x, 3, 1) + ", " +
                                         FloatToString(vTarget.y, 3, 1) + ", " +
                                         FloatToString(vTarget.z, 3, 1) + ")", COLOR_CYAN)) + "\n");

    if (!GetIsObjectValid(oTarget) && vTarget == Vector())
    {
        Notice(HexColorString("Targeted object or position is invalid, no data saved\n", COLOR_RED_LIGHT));
        nValid = FALSE;
    }
    else
    {
        Notice(HexColorString("Saving targeted object and position to PC", COLOR_CYAN) +
                "\n  Tag -> " + HexColorString(GetTag(oTarget), COLOR_CYAN) +
                "\n  Location -> " + HexColorString(__LocationToString(Location(GetArea(oTarget), vTarget, 0.0f)), COLOR_CYAN) +
                "\n  Area -> " + HexColorString(GetTag(GetArea(oTarget)), COLOR_CYAN) + "\n");

        AddListObject(oPC, oTarget, sVarName);
        AddListLocation(oPC, Location(GetArea(oTarget), vTarget, 0.0f), sVarName);
    }

    if (!nValid)
        DeleteTargetingHook(oPC, nHookID);
    else
    {
        if (GetTargetingHookUses(nHookID) == -1)
            EnterTargetingMode(oPC, GetTargetingHookObjectType(nHookID));
        else
            DecrementTargetingHookUses(oPC, nHookID);
    }
}

object GetTargetingHookObject(object oPC, string sVarName, int nIndex = 0)
{
    return GetListObject(oPC, nIndex, sVarName);
}

location GetTargetingHookLocation(object oPC, string sVarName, int nIndex = 0)
{
    return GetListLocation(oPC, nIndex, sVarName);
}

vector GetTargetingHookPosition(object oPC, string sVarName, int nIndex = 0)
{
    location l = GetTargetingHookLocation(oPC, sVarName, nIndex);
    return GetPositionFromLocation(l);
}

int CountTargetingHookTargets(object oPC, string sVarName)
{
    return CountObjectList(oPC, sVarName);
}

int DeleteTargetingHookTarget(object oPC, string sVarName, int nIndex = 0)
{
    DeleteListObject(oPC, nIndex, sVarName);
    return DeleteListLocation(oPC, nIndex, sVarName);
}

void DeleteTargetingHookTargets(object oPC, string sVarName)
{
    DeleteObjectList(oPC, sVarName);
    DeleteLocationList(oPC, sVarName);
}

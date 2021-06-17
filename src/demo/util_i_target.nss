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

This system is designed to take advantage of NWN:EE's ability to forcibly enter
Targeting Mode for any given PC.  It is designed to add a single-use, multi-use,
or unlimited-use hook to the specified PC.  Once the PC has satisfied the conditions
of the hook, or manually exited targeting mode, the targeted objects/locations
will be saved and a specified script will be run.

Setup:

1.  You must attach a targeting event script to the module.  For example, in your
module load script, you can add this line:

    SetEventScript(GetModule(), EVENT_SCRIPT_MODULE_ON_PLAYER_TARGET, "module_opt");

where "module_opt" is the script that will handle all forced targeting.

2.  The chosen script ("module_opt") must contain reference to the util_i_target
function TS_SatisfyTargetingHook().  An example of this follows.

#include util_i_target

void main()
{
    object oPC = GetLastPlayerToSelectTarget();

    if (TS_SatisfyTargetingHook(oPC))
    {
        // This PC was marked as a targeter, do something here.
    }
}

Usage:

The design of this system centers around a module-wide list of "Targeting Hooks"
that are accessed by util_i_target when a player targets any object or
manually exits targeting mode.  These hooks are stored in the module's organic
sqlite database.  All targeting hook information is volatile and will be reset
when the server/module is reset.

This is the prototype for the TS_AddTargetingHook() function:

int TS_AddTargetingHook(object oPC, string sVarName, int nObjectType = OBJECT_TYPE_ALL, string sScript = "", int nUses = 1);

oPC is the PC object that will be associated with this hook.  This PC will be the
    player that will be entered into Targeting Mode.  Additionally, the results of
    his targeting will be saved to the PC object.
sVarName is the variable name to save the results of targeting to.  This allows
    for targeting hooks to be added that can be saved to different variables for
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
    TS_AddTargetingHook(oPC, "spell_target", nObjectType, "temp_target");

To add a multi-use targeting hook that enters the PC into targeting mode, allows
    for the selection of a specified number of placeables | creatures, then runs
    the script "temp_target" upon exiting targeting mode or selecting the
    specified number of targets:

    int nObjectType = OBJECT_TYPE_PLACEABLE | OBJECT_TYPE_CREATURE;
    TS_AddTargetingHook(oPC, "DM_Party", nObjectType, "temp_target", 3);

    Note:  In this case, the player can select up to three targets to save to
        the "DM_Party" variable.

To add an unlmited-use targeting hook that enters the PC into targeting mode, allows
    for the selection of an unspecified number of creatures, then runs
    the script "temp_target" upon exiting targeting mode or selection of an invalid
    target:

    int nObjectType = OBJECT_TYPE_CREATURE;
    TS_AddTargetingHook(oPC, "NPC_Townspeople", nObjectType, "temp_target", -1);

Here is an example "temp_target" post-targeting script that will access each of the
    targets saved to the specified variable and send their data to the chat log:

#include "util_i_target"

void main()
{
    object oPC = OBJECT_SELF;
    int n, nCount = TS_CountTargetingHookTargets(oPC, "NPC_Townspeople");

    for (n = 0; n < nCount; n++)
    {
        object oTarget = GetTargetingHookObject(oPC, "NPC_Townspeople", n);
        location lTarget = GetTargetingHookLocation(oPC, "NPC_Townspeople", n);
        vector vTarget = GetTargetingHookPosition(oPC, "NPC_Townspeople", n);
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
#include "util_i_variable"

// VarList names for the global targeting hook lists
const string TARGET_HOOK_ID = "TARGET_HOOK_ID";
const string TARGET_HOOK_BEHAVIOR = "TARGET_HOOK_BEHAVIOR";

// List Behaviors
const int TARGET_BEHAVIOR_ADD = 1;
const int TARGET_BEHAVIOR_DELETE = 2;

// Targeting Hook Data Structure
struct TargetingHook
{
    int nHookID;
    object oPC;
    string sVarName;
    int nObjectType;
    int nUses;
    string sScript;
};

// -----------------------------------------------------------------------------
//                              Function Prototypes
// -----------------------------------------------------------------------------

// ---< TS_GetTargetingHookDataByHookID >---
// Returns a TargetingHook struct containing all targeting hook data
// associated with nHookID.
struct TargetingHook TS_GetTargetingHookDataByHookID(int nHookID);

// ---< TS_GetTargetingHookDataByVarName >---
// Returns a TargetingHook struct containing all targeting hook data
// associated with oPC's sVarName target list.
struct TargetingHook TS_GetTargetingHookDataByVarName(object oPC, string sVarName);

// ---< TS_GetTargetList >---
// Returns a prepared sqlquery containing the target list associated with
// oPC's sVarName.  If nIndex > 0, this function will return only the target
// associated with target number nIndex in the target list associated with
// oPC's sVarname.
sqlquery TS_GetTargetList(object oPC, string sVarName, int nIndex = -1);

// ---< TS_AddTargetToTargetList >---
// Adds target object oTarget, target's area oArea and target's location vTarget
// to oPC's target list associated with sVarName.  oTarget will be added to the end
// of the list.  Returns the number of targets on target list sVarName.
int TS_AddTargetToTargetList(object oPC, string sVarName, object oTarget, object oArea, vector vTarget);

// ---< TS_DeleteTargetList >---
// Deletes all targets associated with oPC's sVarName target list.
void TS_DeleteTargetList(object oPC, string sVarName);

// ---< TS_DeleteTargetingHook >---
// Deletes all data associated with targeting hook nHookID.
void TS_DeleteTargetingHook(int nHookID);

// ---< TS_EnterTargetingModeByHookID >---
// Forces the PC object associated with targeting hook nHookID to enter targeting
// mode using properties set by TS_AddTargetingHook().
void TS_EnterTargetingModeByHookID(int nHookID, int nBehavior = TARGET_BEHAVIOR_ADD);

// ---< TS_EnterTargetingModeByVarName >---
// Forces oPC to enter targeting mode using properties set by TS_AddTargetingHook().
void TS_EnterTargetingModeByVarName(object oPC, string sVarName, int nBehavior = TARGET_BEHAVIOR_ADD);

// ---< TS_GetTargetingHookID >---
// Returns the targeting hook ID associated with oPC's sVarName target list
int TS_GetTargetingHookID(object oPC, string sVarName);

// ---< TS_GetTargetingHookVarName >---
// Returns the target list name sVarName associated with nHookID
string TS_GetTargetingHookVarName(int nHookID);

// ---< TS_GetTargetingHookObjectType >---
// Returns the targetable object types nObjectType associated with nHookID
int TS_GetTargetingHookObjectType(int nHookID);

// ---< TS_GetTargetingHookUses >---
// Returns the number of target hook uses remaining for the targeting hook
// associated with nHookID
int TS_GetTargetingHookUses(int nHookID);

// ---< TS_GetTargetingHookScript >---
// Returns the targeting script sScript associated with nHookID
string TS_GetTargetingHookScript(int nHookID);

// ---< TS_AddTargetingHook >---
// Adds a targeting hook to the global targeting hook list and saves the desired
// variable name sVarName, nObjectType and number of uses remaining nUses.
int TS_AddTargetingHook(object oPC, string sVarName, int nObjectType = OBJECT_TYPE_ALL, 
        string sScript = "", int nUses = 1);

// ---< SatisfyTargetingHook >---
// Saves the targeting data to the PC object as an object and location variable
// defined by sVarName in AddTargetingHook.  Decrements remaining hook uses and,
// if required, deletes the targeting hook.  Returns TRUE if oPC has a hook
// assigned, FALSE otherwise.
int TS_SatisfyTargetingHook(object oPC);

// ---< TS_GetTargetingHookObject >---
// Returns the object associated with oPC's sVarName target list at position nIndex.
// if nIndex is not passed, the first target on the target list sVarName will be returned.
object TS_GetTargetingHookObject(object oPC, string sVarName, int nIndex = 1);

// ---< TS_GetTargetingHookLocation >---
// Returns the location associated with oPC's sVarName target list at position nIndex.
// if nIndex is not passed, the first location on the target list sVarName will be returned.
location TS_GetTargetingHookLocation(object oPC, string sVarName, int nIndex = 1);

// ---< TS_GetTargetingHookPosition >---
// Returns the position associated with oPC's sVarName target list at position nIndex.
// if nIndex is not passed, the first position on the target list sVarName will be returned.
vector TS_GetTargetingHookPosition(object oPC, string sVarName, int nIndex = 1);

// ---< TS_CountTargetingHookTargets >---
// Returns the number of targets associated with the target saved as sVarName on
// oPC.  This will normally be one except in the case of a multi-use hook.
int TS_CountTargetingHookTargets(object oPC, string sVarName);

// ---< DeleteTargetingHookTarget >---
// Removes the target data saved on oPC under sVarName at nIndex.  if nIndex is not
// passed, the first target on target list sVarName will be deleted.
int TS_DeleteTargetingHookTarget(object oPC, string sVarName, int nIndex = 1);

// ---< TS_DeleteTargetingHookTargetByIndex >---
// Removes a specific targets from the global target listing.  nIndex is the
// TargetID as retrieved from TS_GetTargetingHookIndex().
int TS_DeleteTargetingHookTargetByIndex(object oPC, string sVarName, int nIndex);

// ---< TS_GetTargetingHookIndex >---
// Returns the Index (nTargetID) of oTarget from oPC's target list sVarName.
int TS_GetTargetingHookIndex(object oPC, string sVarName, object oTarget);

// -----------------------------------------------------------------------------
//                            Private Function Definitions
// -----------------------------------------------------------------------------

string _GetTargetingHookFieldData(int nHookID, string sField)
{
    string sQuery = "SELECT " + sField + " " +
                    "FROM targeting_hooks " +
                    "WHERE nHookID = @nHookID;";
    sqlquery sql = SqlPrepareQueryObject(GetModule(), sQuery);
    SqlBindInt(sql, "@nHookID", nHookID);

    return SqlStep(sql) ? SqlGetString(sql, 0) : "";
}

void _CreateTargetingDataTables(int bReset = FALSE)
{
    object oModule = GetModule();

    if (bReset)
    {
        string sDropHooks = "DROP TABLE IF EXISTS targeting_hooks;";
        string sDropTargets = "DROP TABLE IF EXISTS targeting_targets;";

        sqlquery sql;
        sql = SqlPrepareQueryObject(oModule, sDropHooks);   SqlStep(sql);
        sql = SqlPrepareQueryObject(oModule, sDropTargets); SqlStep(sql);

        DeleteLocalInt(oModule, "TARGETING_INITIALIZED");

        Notice(HexColorString("Targeting database tables have been dropped", COLOR_RED_LIGHT));
    }

    if (GetLocalInt(oModule, "TARGETING_INITIALIZED") == TRUE) return;

    string sData = "CREATE TABLE IF NOT EXISTS targeting_hooks (" +
        "nHookID INTEGER PRIMARY KEY AUTOINCREMENT, " +
        "sUUID TEXT, " +
        "sVarName TEXT, " +
        "nObjectType INTEGER, " +
        "nUses INTEGER default '1', " +
        "sScript TEXT, " +
        "UNIQUE (sUUID, sVarName));";

    string sTargets = "CREATE TABLE IF NOT EXISTS targeting_targets (" +
        "nTargetID INTEGER PRIMARY KEY AUTOINCREMENT, " +
        "sUUID TEXT, " +
        "sVarName TEXT, " +
        "sTargetObject TEXT, " +
        "sTargetArea TEXT, " +
        "vTargetLocation TEXT);";

    sqlquery sql;
    sql = SqlPrepareQueryObject(oModule, sData);  SqlStep(sql);
    sql = SqlPrepareQueryObject(oModule, sTargets);  SqlStep(sql);

    Notice(HexColorString("Targeting database tables have been created", COLOR_GREEN_LIGHT));
    SetLocalInt(oModule, "TARGETING_INITIALIZED", TRUE);
}

int _GetLastTargetingHookID()
{
    string sQuery = "SELECT seq FROM sqlite_sequence WHERE name = @name;";
    sqlquery sql = SqlPrepareQueryObject(GetModule(), sQuery);
    SqlBindString(sql, "@name", "targeting_hooks");
    
    return SqlStep(sql) ? SqlGetInt(sql, 0) : 0;
}

void _EnterTargetingMode(object oPC, int nObjectType, int nHookID, int nBehavior)
{
    SetLocalInt(oPC, TARGET_HOOK_ID, nHookID);
    SetLocalInt(oPC, TARGET_HOOK_BEHAVIOR, nBehavior);
    EnterTargetingMode(oPC, nObjectType, MOUSECURSOR_MAGIC, MOUSECURSOR_NOMAGIC);
}

string _GetTargetData(object oPC, string sVarName, string sField, int nIndex = 1)
{
    string sQuery = "SELECT " + sField + " " +
                    "FROM targeting_targets " +
                    "WHERE sUUID = @sUUID " +
                        "AND sVarName = @sVarName " +
                    "LIMIT 1 OFFSET " + IntToString(nIndex) + ";";
    sqlquery sql = SqlPrepareQueryObject(GetModule(), sQuery);
    SqlBindString(sql, "@sUUID", GetObjectUUID(oPC));
    SqlBindString(sql, "@sVarName", sVarName);

    return SqlStep(sql) ? SqlGetString(sql, 0) : "";
}

void _DeleteTargetingHookData(int nHookID)
{
    string sQuery = "DELETE FROM targeting_hooks " +
                    "WHERE nHookID = @nHookID;";
    sqlquery sql = SqlPrepareQueryObject(GetModule(), sQuery);
    SqlBindInt(sql, "@nHookID", nHookID);
    SqlStep(sql);
}

// Reduces the number of targeting hooks remaining.  When the remaining number is
// 0, the hook is automatically deleted.
int _DecrementTargetingHookUses(object oPC, int nHookID, int nBehavior)
{
    int nUses = TS_GetTargetingHookUses(nHookID);
    
    if (--nUses == 0)
    {
        Notice("Decrementing target hook uses for ID " + HexColorString(IntToString(nHookID), COLOR_CYAN) +
               "\n  Uses remaining -> " + (nUses ? HexColorString(IntToString(nUses), COLOR_CYAN) : HexColorString(IntToString(nUses), COLOR_RED_LIGHT)) + "\n");
        TS_DeleteTargetingHook(nHookID);
    }
    else
    {
        string sQuery = "UPDATE targeting_hooks " +
                        "SET nUses = nUses - 1 " +
                        "WHERE nHookID = @nHookID;";
        sqlquery sql = SqlPrepareQueryObject(GetModule(), sQuery);
        SqlBindInt(sql, "@nHookID", nHookID);
        SqlStep(sql);
        
        _EnterTargetingMode(oPC, TS_GetTargetingHookObjectType(nHookID), nHookID, nBehavior);
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

struct TargetingHook TS_GetTargetingHookDataByHookID(int nHookID)
{
    string sQuery = "SELECT nHookID, sUUID, sVarName, nObjectType, nUses, sScript " +
                    "FROM targeting_hooks " +
                    "WHERE nHookID = @nHookID;";
    sqlquery sql = SqlPrepareQueryObject(GetModule(), sQuery);
    SqlBindInt(sql, "@nHookID", nHookID);
    
    struct TargetingHook th;
    SqlStep(sql);
    
    th.nHookID = SqlGetInt(sql, 0);
    th.oPC = GetObjectByUUID(SqlGetString(sql, 1));
    th.sVarName = SqlGetString(sql, 2);
    th.nObjectType = SqlGetInt(sql, 3);
    th.nUses = SqlGetInt(sql, 4);
    th.sScript = SqlGetString(sql, 5);

    return th;
}

struct TargetingHook TS_GetTargetingHookDataByVarName(object oPC, string sVarName)
{
    int nHookID = TS_GetTargetingHookID(oPC, sVarName);
    return TS_GetTargetingHookDataByHookID(nHookID);
}

sqlquery TS_GetTargetList(object oPC, string sVarName, int nIndex = -1)
{   // TODO NWNSC doesn't do structs in structs (i.e. vectors into structs), so find a way around this to use a struct?
    string sQuery = "SELECT sTargetObject, sTargetArea, vTargetLocation " +
                    "FROM targeting_targets " +
                    "WHERE sUUID = @sUUID " +
                        "AND sVarName = @sVarName" +
                    (nIndex == -1 ? ";" : "LIMIT 1 OFFSET " + IntToString(nIndex)) + ";";
    sqlquery sql = SqlPrepareQueryObject(GetModule(), sQuery);
    SqlBindString(sql, "@sUUID", GetObjectUUID(oPC));
    SqlBindString(sql, "@sVarName", sVarName);

    return sql;
}

int TS_AddTargetToTargetList(object oPC, string sVarName, object oTarget, object oArea, vector vTarget)
{
    string sQuery = "INSERT INTO targeting_targets (sUUID, sVarName, sTargetObject, sTargetArea, vTargetLocation) " +
        "VALUES (@sUUID, @sVarName, @sTargetObject, @sTargetArea, @vTargetLocation);";
    sqlquery sql = SqlPrepareQueryObject(GetModule(), sQuery);
    SqlBindString(sql, "@sUUID", GetObjectUUID(oPC));
    SqlBindString(sql, "@sVarName", sVarName);
    SqlBindString(sql, "@sTargetObject", ObjectToString(oTarget));
    SqlBindString(sql, "@sTargetArea", ObjectToString(oArea));
    SqlBindVector(sql, "@vTargetLocation", vTarget);

    SqlStep(sql);

    return TS_CountTargetingHookTargets(oPC, sVarName);
}

void TS_DeleteTargetList(object oPC, string sVarName)
{
    string sQuery = "DELETE FROM targeting_targets " +
                    "WHERE sUUID = @sUUID " +
                        "AND sVarName = @sVarName;";
    sqlquery sql = SqlPrepareQueryObject(GetModule(), sQuery);
    SqlBindString(sql, "@sUUID", GetObjectUUID(oPC));
    SqlBindString(sql, "@sVarName", sVarName);

    SqlStep(sql);
}

void TS_EnterTargetingModeByHookID(int nHookID, int nBehavior = TARGET_BEHAVIOR_ADD)
{
    struct TargetingHook th = TS_GetTargetingHookDataByHookID(nHookID);

    if (GetIsObjectValid(th.oPC))
        _EnterTargetingMode(th.oPC, th.nObjectType, nHookID, nBehavior);
}

void TS_EnterTargetingModeByVarName(object oPC, string sVarName, int nBehavior = TARGET_BEHAVIOR_ADD)
{
    struct TargetingHook th = TS_GetTargetingHookDataByVarName(oPC, sVarName);
    if (GetIsObjectValid(th.oPC))
        _EnterTargetingMode(th.oPC, th.nObjectType, th.nHookID, nBehavior);
}

int TS_GetTargetingHookID(object oPC, string sVarName)
{
    string sQuery = "SELECT nHookID " +
                    "FROM targeting_hooks " +
                    "WHERE sUUID = @sUUID " +
                        "AND sVarName =@sVarName;";
    sqlquery sql = SqlPrepareQueryObject(GetModule(), sQuery);
    SqlBindString(sql, "@sUUID", GetObjectUUID(oPC));
    SqlBindString(sql, "@sVarName", sVarName);

    return SqlStep(sql) ? SqlGetInt(sql, 0) : 0;
}

string TS_GetTargetingHookVarName(int nHookID)
{
    return _GetTargetingHookFieldData(nHookID, "sVarName");
}

int TS_GetTargetingHookObjectType(int nHookID)
{
    return StringToInt(_GetTargetingHookFieldData(nHookID, "nObjectType"));
}

int TS_GetTargetingHookUses(int nHookID)
{
    return StringToInt(_GetTargetingHookFieldData(nHookID, "nUses"));
}

string TS_GetTargetingHookScript(int nHookID)
{
    return _GetTargetingHookFieldData(nHookID, "sScript");
}

int TS_AddTargetingHook(object oPC, string sVarName, int nObjectType = OBJECT_TYPE_ALL, 
        string sScript = "", int nUses = 1)
{
    _CreateTargetingDataTables();

    object oModule = GetModule();
    string sQuery = "INSERT INTO targeting_hooks (sUUID, sVarName, nObjectType, nUses, sScript) " +
        "VALUES (@sUUID, @sVarName, @nObjectType, @nUses, @sScript) " +
        "ON CONFLICT (sUUID, sVarName) DO UPDATE " +
            "SET nObjectType = @nObjectType, nUses = @nUses, sScript = @sScript;";
    sqlquery sql = SqlPrepareQueryObject(oModule, sQuery);
    SqlBindString(sql, "@sUUID", GetObjectUUID(oPC));
    SqlBindString(sql, "@sVarName", sVarName);
    SqlBindInt(sql, "@nObjectType", nObjectType);
    SqlBindInt(sql, "@nUses", nUses);
    SqlBindString(sql, "@sScript", sScript);
    SqlStep(sql);

    Notice("Adding targeting hook ID " + HexColorString(IntToString(_GetLastTargetingHookID()), COLOR_CYAN) +
        "\n  sVarName -> " + HexColorString(sVarName, COLOR_CYAN) +
        "\n  nObjectType -> " + HexColorString(ObjectTypeToString(nObjectType), COLOR_CYAN) +
        "\n  sScript -> " + (sScript == "" ? HexColorString("[None]", COLOR_RED_LIGHT) : 
            HexColorString(sScript, COLOR_CYAN)) +
        "\n  nUses -> " + (nUses == -1 ? HexColorString("Unlimited", COLOR_CYAN) : 
            (nUses > 0 ? HexColorString(IntToString(nUses), COLOR_CYAN) : 
            HexColorString(IntToString(nUses), COLOR_RED_LIGHT))) + "\n");


    return _GetLastTargetingHookID();
}

void TS_DeleteTargetingHook(int nHookID)
{
    struct TargetingHook th = TS_GetTargetingHookDataByHookID(nHookID);
    
    Notice("Deleting targeting hook ID " + HexColorString(IntToString(nHookID), COLOR_CYAN) + "\n");

    _DeleteTargetingHookData(nHookID);
    DeleteLocalInt(th.oPC, TARGET_HOOK_ID);
    DeleteLocalInt(th.oPC, TARGET_HOOK_BEHAVIOR);

    if (th.sScript != "")
    {
        Notice("Running post-targeting script " + th.sScript);
        ExecuteScript(th.sScript, th.oPC);
    }
    else
        Notice("No post-targeting script specified");    
}

int TS_SatisfyTargetingHook(object oPC)
{
    int nHookID = GetLocalInt(oPC, TARGET_HOOK_ID);
    if (nHookID == 0)
        return FALSE;

    int nBehavior = GetLocalInt(oPC, TARGET_HOOK_BEHAVIOR);

    struct TargetingHook th = TS_GetTargetingHookDataByHookID(nHookID);

    string sVarName = th.sVarName;
    object oTarget = GetTargetingModeSelectedObject();
    vector vTarget = GetTargetingModeSelectedPosition();

    int bValid = TRUE;

    Notice("Targeted Object -> " + (GetIsObjectValid(oTarget) ? (GetIsPC(oTarget) ? HexColorString(GetName(oTarget), COLOR_GREEN_LIGHT) : HexColorString(GetTag(oTarget), COLOR_CYAN)) : HexColorString("OBJECT_INVALID", COLOR_RED_LIGHT)) +
           "\n  Type -> " + HexColorString(ObjectTypeToString(GetObjectType(oTarget)), COLOR_CYAN));
    Notice("Targeted Position -> " + (vTarget == Vector() ? HexColorString("POSITION_INVALID", COLOR_RED_LIGHT) :
                                    HexColorString("(" +FloatToString(vTarget.x, 3, 1) + ", " +
                                         FloatToString(vTarget.y, 3, 1) + ", " +
                                         FloatToString(vTarget.z, 3, 1) + ")", COLOR_CYAN)) + "\n");

    if (GetIsObjectValid(oTarget) == FALSE && vTarget == Vector())
    {
        Notice(HexColorString("Targeted object or position is invalid, no data saved\n", COLOR_RED_LIGHT));
        bValid = FALSE;
    }
    else
    {
        if (nBehavior == TARGET_BEHAVIOR_ADD)
        {
            Notice(HexColorString("Saving targeted object and position to list [" + th.sVarName + "]:", COLOR_CYAN) +
                    "\n  Tag -> " + HexColorString(GetTag(oTarget), COLOR_CYAN) +
                    "\n  Location -> " + HexColorString(__LocationToString(Location(GetArea(oTarget), vTarget, 0.0f)), COLOR_CYAN) +
                    "\n  Area -> " + HexColorString(GetTag(GetArea(oTarget)), COLOR_CYAN) + "\n");
            
            TS_AddTargetToTargetList(oPC, sVarName, oTarget, GetArea(oPC), vTarget);
        }
        else if (nBehavior == TARGET_BEHAVIOR_DELETE)
        {
            if (GetArea(oTarget) == oTarget)
                Notice("Location/Tile targets cannot be deleted; select a game object");
            else
            {
                Notice(HexColorString("Attempting to delete targeted object and position from list [" + th.sVarName + "]:", COLOR_CYAN));
                int nIndex = TS_GetTargetingHookIndex(oPC, sVarName, oTarget);
                if (nIndex == 0)
                    Notice("  > " + HexColorString("Target " + (GetIsPC(oTarget) ? GetName(oTarget) : GetTag(oTarget)) + " not found " +
                        "on list [" + th.sVarName + "]; removal aborted", COLOR_RED_LIGHT));
                else
                {
                    TS_DeleteTargetingHookTargetByIndex(oPC, sVarName, nIndex);
                    Notice("  > " + HexColorString("Target " + (GetIsPC(oTarget) ? GetName(oTarget) : GetTag(oTarget)) + " removed from " +
                        "list [" + th.sVarName + "]", COLOR_GREEN_LIGHT));
                }
            }
        }
    }

    if (bValid == FALSE)
        TS_DeleteTargetingHook(nHookID);
    else
    {
        if (th.nUses == -1)
            _EnterTargetingMode(oPC, th.nObjectType, nHookID, nBehavior);
        else
            _DecrementTargetingHookUses(oPC, nHookID, nBehavior);
    }

    return TRUE;
}

int TS_DeleteTargetingHookTargetByIndex(object oPC, string sVarName, int nIndex)
{
    string sQuery = "DELETE FROM targeting_targets " +
                    "WHERE nTargetID = @nTargetID;";
    sqlquery sql = SqlPrepareQueryObject(GetModule(), sQuery);
    SqlBindInt(sql, "@nTargetID", nIndex);

    SqlStep(sql);
    return TS_CountTargetingHookTargets(oPC, sVarName);
}

int TS_GetTargetingHookIndex(object oPC, string sVarName, object oTarget)
{
    string sQuery = "SELECT nTargetID " +
                    "FROM targeting_targets " +
                    "WHERE sUUID = @sUUID " +
                        "AND sVarName = @sVarName " +
                        "AND sTargetObject = @sTargetObject;";
    sqlquery sql = SqlPrepareQueryObject(GetModule(), sQuery);
    SqlBindString(sql, "@sUUID", GetObjectUUID(oPC));
    SqlBindString(sql, "@sVarName", sVarName);
    SqlBindString(sql, "@sTargetObject", ObjectToString(oTarget));

    return SqlStep(sql) ? SqlGetInt(sql, 0) : 0;
}

object TS_GetTargetingHookObject(object oPC, string sVarName, int nIndex = 1)
{
    return StringToObject(_GetTargetData(oPC, sVarName, "sTargetObject", nIndex));
}

location TS_GetTargetingHookLocation(object oPC, string sVarName, int nIndex = 1)
{
    sqlquery sql = TS_GetTargetList(oPC, sVarName, 1);
    if (SqlStep(sql))
    {
        object oArea = StringToObject(SqlGetString(sql, 1));
        vector vTarget = SqlGetVector(sql, 2);

        return Location(oArea, vTarget, 0.0);
    }

    return Location(OBJECT_INVALID, Vector(), 0.0);
}

vector TS_GetTargetingHookPosition(object oPC, string sVarName, int nIndex = 1)
{
    sqlquery sql = TS_GetTargetList(oPC, sVarName, 1);
    if (SqlStep(sql))
        return SqlGetVector(sql, 2);

    return Vector();
}

int TS_CountTargetingHookTargets(object oPC, string sVarName)
{
    string sQuery = "SELECT COUNT (nTargetID) " +
                    "FROM targeting_targets " +
                    "WHERE sUUID = @sUUID " +
                        "AND sVarName = @sVarName;";
    sqlquery sql = SqlPrepareQueryObject(GetModule(), sQuery);
    SqlBindString(sql, "@sUUID", GetObjectUUID(oPC));
    SqlBindString(sql, "@sVarName", sVarName);

    return SqlStep(sql) ? SqlGetInt(sql, 0) : 0;
}

int TS_DeleteTargetingHookTarget(object oPC, string sVarName, int nIndex = 1)
{
    string sQuery = "DELETE FROM targeting_targets " +
                    "WHERE sUUID = @sUUID " +
                        "AND sVarName = @sVarName " +
                    "LIMIT 1 OFFSET " + IntToString(nIndex) + ";";
    sqlquery sql = SqlPrepareQueryObject(GetModule(), sQuery);
    SqlBindString(sql, "@sUUID", GetObjectUUID(oPC));
    SqlBindString(sql, "@sVarName", sVarName);

    SqlStep(sql);
    
    return TS_CountTargetingHookTargets(oPC, sVarName);
}

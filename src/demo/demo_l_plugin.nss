// -----------------------------------------------------------------------------
//    File: demo_l_plugin.nss
//  System: Core Framework Demo (library script)
//     URL: https://github.com/squattingmonk/nwn-core-framework
// Authors: Michael A. Sinclair (Squatting Monk) <squattingmonk@gmail.com>
// -----------------------------------------------------------------------------
// This library script contains scripts to hook in to Core Framework events.
// -----------------------------------------------------------------------------

#include "util_i_color"
#include "util_i_library"
#include "core_i_framework"
#include "chat_i_main"

#include "util_i_target"

// -----------------------------------------------------------------------------
//                                  VerifyEvent
// -----------------------------------------------------------------------------
// This is a simple script that sends a message to the PC triggering an event.
// It can be used to verify that an event is firing as expected.
// -----------------------------------------------------------------------------

void VerifyEvent(object oPC)
{
    object oEvent = GetCurrentEvent();
    SendMessageToPC(oPC, GetName(oEvent) + " fired!");
}

// -----------------------------------------------------------------------------
//                                  PrintColors
// -----------------------------------------------------------------------------
// Prints a list of color strings for the calling PC. Used to test util_i_color.
// -----------------------------------------------------------------------------

void PrintColor(object oPC, string sColor, int nColor)
{
    SendMessageToPC(oPC, HexColorString(sColor + ": " + IntToHexString(nColor), nColor));
}

void PrintHexColor(object oPC, int nColor)
{
    string sText = "The quick brown fox jumps over the lazy dog";
    string sMessage = IntToHexString(nColor) + ": " + sText;
    SendMessageToPC(oPC, HexColorString(sMessage, nColor));
}

void PrintColors(object oPC)
{
    PrintColor(oPC, "Black", COLOR_BLACK);
    PrintColor(oPC, "Blue", COLOR_BLUE);
    PrintColor(oPC, "Dark Blue", COLOR_BLUE_DARK);
    PrintColor(oPC, "Light Blue", COLOR_BLUE_LIGHT);
    PrintColor(oPC, "Brown", COLOR_BROWN);
    PrintColor(oPC, "Light Brown", COLOR_BROWN_LIGHT);
    PrintColor(oPC, "Divine", COLOR_DIVINE);
    PrintColor(oPC, "Gold", COLOR_GOLD);
    PrintColor(oPC, "Gray", COLOR_GRAY);
    PrintColor(oPC, "Dark Gray", COLOR_GRAY_DARK);
    PrintColor(oPC, "Light Gray", COLOR_GRAY_LIGHT);
    PrintColor(oPC, "Green", COLOR_GREEN);
    PrintColor(oPC, "Dark Green", COLOR_GREEN_DARK);
    PrintColor(oPC, "Light Green", COLOR_GREEN_LIGHT);
    PrintColor(oPC, "Orange", COLOR_ORANGE);
    PrintColor(oPC, "Dark Orange", COLOR_ORANGE_DARK);
    PrintColor(oPC, "Light Orange", COLOR_ORANGE_LIGHT);
    PrintColor(oPC, "Red", COLOR_RED);
    PrintColor(oPC, "Dark Red", COLOR_RED_DARK);
    PrintColor(oPC, "Light Red", COLOR_RED_LIGHT);
    PrintColor(oPC, "Pink", COLOR_PINK);
    PrintColor(oPC, "Purple", COLOR_PURPLE);
    PrintColor(oPC, "Turquoise", COLOR_TURQUOISE);
    PrintColor(oPC, "Violet", COLOR_VIOLET);
    PrintColor(oPC, "Light Violet", COLOR_VIOLET_LIGHT);
    PrintColor(oPC, "Dark Violet", COLOR_VIOLET_DARK);
    PrintColor(oPC, "White", COLOR_WHITE);
    PrintColor(oPC, "Yellow", COLOR_YELLOW);
    PrintColor(oPC, "Dark Yellow", COLOR_YELLOW_DARK);
    PrintColor(oPC, "Light Yellow", COLOR_YELLOW_LIGHT);

    PrintHexColor(oPC, 0x0099fe);
    PrintHexColor(oPC, 0x3dc93d);

    struct HSV hsv = HexToHSV(0xff0000);
    PrintHexColor(oPC, HSVToHex(hsv));
    SendMessageToPC(oPC, "H: " + FloatToString(hsv.h) +
                        " S: " + FloatToString(hsv.s) +
                        " V: " + FloatToString(hsv.v));
    hsv.v /= 2.0;
    hsv.s = 0.0;
    PrintHexColor(oPC, HSVToHex(hsv));
}

void core_OnModuleLoad()
{
    SetEventScript(GetModule(), EVENT_SCRIPT_MODULE_ON_PLAYER_TARGET, "hook_nwn");
}

void core_TargetingMode(object oPC)
{   
    string TARGET_HOOK_VARNAME = "TARGET_HOOK_VARNAME";

    int nObjectType = OBJECT_TYPE_PLACEABLE | OBJECT_TYPE_CREATURE;
    if (HasChatOption(oPC, "a,all"))
        nObjectType = OBJECT_TYPE_ALL;

    int nCount = GetChatKeyValueInt(oPC, "count");
    if (nCount == 0) nCount = 1;

    if (HasChatOption(oPC, "r,reset"))
        _CreateTargetingDataTables(TRUE);

    int nHookID = TS_AddTargetingHook(oPC, TARGET_HOOK_VARNAME, nObjectType, "temp_target", nCount);

    TS_DeleteTargetList(oPC, TARGET_HOOK_VARNAME);
    TS_EnterTargetingModeByHookID(nHookID);

    Notice(HexColorString("Select any target to save that target's data to the PC's object", COLOR_CYAN) +
           "\n  " + (nObjectType == OBJECT_TYPE_ALL ? "Target selection is not limited by type" : "Target selection is limited to " + HexColorString(ObjectTypeToString(nObjectType), COLOR_CYAN)) + "\n");
}

void core_OnPlayerTarget()
{
    object oPC = GetLastPlayerToSelectTarget();
    TS_SatisfyTargetingHook(oPC);
}

int GetLastInsertedID(string sTable)
{
    string sQuery = "SELECT seq FROM sqlite_sequence WHERE name = @name;";
    sqlquery sql = SqlPrepareQueryObject(GetModule(), sQuery);
    SqlBindString(sql, "@name", sTable);
    
    return SqlStep(sql) ? SqlGetInt(sql, 0) : -1;
}

void test_db()
{
    object oPC = GetPCChatSpeaker();
    string db = "TEST_DB";

    if (HasChatOption(oPC, "c"))
    {
        string sParent = "CREATE TABLE IF NOT EXISTS table_parent (" +
            "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
            "data TEXT);";
        string sChild = "CREATE TABLE IF NOT EXISTS table_child (" +
            "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
            "parent_id INTEGER, " +
            "data TEXT, " +
            "FOREIGN KEY (parent_id) REFERENCES table_parent (id) " +
                "ON DELETE CASCADE ON UPDATE CASCADE);";

        sqlquery sql;
        sql = SqlPrepareQueryCampaign(db, sParent); SqlStep(sql);
        sql = SqlPrepareQueryCampaign(db, sChild); SqlStep(sql);

        Notice("Created db tables for " + db);
    }

    if (HasChatOption(oPC, "a"))
    {
        string sQuery = "INSERT INTO table_parent (data) " +
                        "VALUES (@data);";
        sqlquery sql = SqlPrepareQueryCampaign(db, sQuery);
        SqlBindString(sql, "@data", "parent test string");

        SqlStep(sql);

        int id = GetLastInsertedID("table_parent");
        sQuery = "INSERT INTO table_child (parent_id, data) " +
                 "VALUES (@parent_id, @data);";
        sql = SqlPrepareQueryCampaign(db, sQuery);
        SqlBindInt(sql, "@parent_id", id);
        SqlBindString(sql, "@data", "child test string");

        SqlStep(sql);

        Notice("Added records to db tables");
    }

    if (HasChatOption(oPC, "d"))
    {
        string sQuery = "DELETE FROM table_parent;";
        sqlquery sql = SqlPrepareQueryCampaign(db, sQuery);
        SqlStep(sql);

        Notice("Deleted records from db tables");
    }
}

// -----------------------------------------------------------------------------
//                               Library Dispatch
// -----------------------------------------------------------------------------

void OnLibraryLoad()
{
    if (!GetIfPluginExists("core_demo"))
    {
        object oPlugin = GetPlugin("core_demo", TRUE);
        SetName(oPlugin, "[Plugin] Core Framework Demo");
        SetDescription(oPlugin,
            "This plugin provides some simple demos of the Core Framework.");

        RegisterEventScripts(oPlugin, PLACEABLE_EVENT_ON_USED, "VerifyEvent");
        RegisterEventScripts(oPlugin, "CHAT_!colors", "PrintColors");
        RegisterEventScripts(oPlugin, "CHAT_!target", "core_TargetingMode");
        RegisterEventScripts(oPlugin, MODULE_EVENT_ON_MODULE_LOAD, "core_OnModuleLoad");
        RegisterEventScripts(oPlugin, MODULE_EVENT_ON_PLAYER_TARGET, "core_OnPlayerTarget");

        RegisterEventScripts(oPlugin, "CHAT_!db", "test_db");
    }

    RegisterLibraryScript("VerifyEvent", 1);
    RegisterLibraryScript("PrintColors", 2);
    RegisterLibraryScript("core_OnModuleLoad", 3);
    RegisterLibraryScript("core_TargetingMode", 4);
    RegisterLibraryScript("core_OnPlayerTarget", 5);

    RegisterLibraryScript("test_db", 10);
}

void OnLibraryScript(string sScript, int nEntry)
{
    object oPC = GetEventTriggeredBy();
    switch (nEntry)
    {
        case 1: VerifyEvent(oPC); break;
        case 2: PrintColors(oPC); break;
        case 3: core_OnModuleLoad(); break;
        case 4: core_TargetingMode(oPC); break;
        case 5: core_OnPlayerTarget(); break;

        case 10: test_db(); break;
        default:
            CriticalError("Library function " + sScript + " not found");
    }
}

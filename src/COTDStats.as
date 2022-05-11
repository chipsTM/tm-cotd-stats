[Setting category="Display Settings" name="Window visible" description="To move the table, click and drag while the Openplanet overlay is visible"]
bool windowVisible = true;

[Setting category="Display Settings" name="Show Div Delta" description="Shows your delta time for the different divisions"]
bool showDivDelta = false;

[Setting category="Display Settings" name="Show lower bound" description="Disabled by default"]
bool showLowerBound = false;

[Setting category="Display Settings" name="Show additional division cutoffs" description="Disabled by default"]
bool showExtraDivs = false;

[Setting category="Display Settings" name="Locator mode" description="Shows the window outside COTD so you can drag it around"]
bool locatorMode = false;

const int MAX_DIV_TIME = 9999999;
// MAX_DIV_TIME of 9999999 is 10k seconds.
// We can safely `>> 3` is roughly division by 8 (which is still 1k+ seconds).
// Since COTD is at most ~120s, we can safely assume values for .time that are greater than (MAX_DIV_TIME >> 3) are dummy times.
// So we use `MAX_DIV_TIME >> 3` as a comparison value.

class DivTime {
    string div;
    int time;
    string style;
    bool hidden;

    DivTime(string div = "--", int time = MAX_DIV_TIME, string style = "\\$fff", bool hidden = true) {
        this.div = div;
        this.time = time;
        this.style = style;
        this.hidden = hidden;
    }

    string DivString() {
        return this.style + ((this.div == "0") ? "--" : this.div) + "\\$z";
    }

    string TimeString() {
        return this.style + (((this.time > 0) && (this.time < MAX_DIV_TIME >> 3)) ? Time::Format(this.time) : "-:--.---") + "\\$z";
    }

    int opCmp(DivTime@ other) {
        int diff = this.time - other.time;
        return (diff == 0) ? 0 : ((diff > 0) ? 1 : -1);
	}
}

// Global variables
string cotdName = "<COTD Name>";
int totalPlayers = 0;
int curdiv = 0;

DivTime@ div1 = DivTime("1", 0, "\\$fff", false);
DivTime@ nextdiv = DivTime("--", MAX_DIV_TIME, "\\$fff");
DivTime@ lowerbounddiv = DivTime("--", MAX_DIV_TIME, "\\$fff", !showLowerBound);
DivTime@ pb = DivTime("--", MAX_DIV_TIME, "\\$0ff", false);

DivTime@ nextnextdiv = DivTime("--", MAX_DIV_TIME, "\\$fff");
DivTime@ belowdiv = DivTime("--", MAX_DIV_TIME, "\\$fff");

// to track when pb changes
DivTime@ lastPb = DivTime("--", MAX_DIV_TIME, "\\$0ff", false);
bool flag_api_haveNewPb = false;

array<DivTime@> divs = { pb, div1, nextnextdiv, nextdiv, lowerbounddiv, belowdiv };

GameInfo@ gameInfo;

void Render() {
#if TMNEXT
    bool showWindow = windowVisible && gameInfo !is null && gameInfo.IsCotd();
    if (showWindow || locatorMode) {

        int windowFlags = UI::WindowFlags::NoTitleBar | UI::WindowFlags::NoCollapse | UI::WindowFlags::AlwaysAutoResize | UI::WindowFlags::NoDocking;

        if (!UI::IsOverlayShown()) {
            windowFlags |= UI::WindowFlags::NoInputs;
        }

// We need a different window name to run multiple copies of the plugin (otherwise everything gets drawn in one window)
#if DEV
        UI::Begin("COTD Qualifying (Dev)", windowFlags);
#else
        UI::Begin("COTD Qualifying", windowFlags);
#endif

        UI::PushStyleVar(UI::StyleVar::ItemSpacing, vec2(0, 0));
        UI::Dummy(vec2(0, 0));
        UI::PopStyleVar();

        UI::BeginGroup();

        UI::BeginTable("header", 1, UI::TableFlags::SizingFixedFit);
        UI::TableNextRow();
        UI::TableNextColumn();
        UI::Text(cotdName);
        UI::TableNextRow();
        UI::TableNextColumn();
        UI::Text("\\$aaa" + totalPlayers + " players (" + Math::Ceil(totalPlayers/64.0) + " divs)\\$z");
        UI::EndTable();

        if (showDivDelta) {
            UI::BeginTable("ranking", 3, UI::TableFlags::SizingFixedFit);
        } else {
            UI::BeginTable("ranking", 2, UI::TableFlags::SizingFixedFit);
        }

        UI::TableNextRow();
        UI::TableNextColumn();
        UI::Text("Div");
        UI::TableNextColumn();
        UI::Text("Cutoff");

        if (showDivDelta) {
            UI::TableNextColumn();
            UI::Text("Delta");
        }

        for(uint i = 0; i < divs.Length; i++) {
            if(divs[i].hidden) {
                continue;
            }
            UI::TableNextRow();
            UI::TableNextColumn();
            UI::Text(divs[i].DivString());
            UI::TableNextColumn();
            UI::Text(divs[i].TimeString());

            if (showDivDelta && !divs[i].hidden) {
                UI::TableNextColumn();
                int deltaTime = pb.time - divs[i].time;
                if (deltaTime != 0 && pb.time < MAX_DIV_TIME >> 3 && divs[i].time < MAX_DIV_TIME >> 3) {
                    UI::Text(((deltaTime >= 0) ? "\\$F70+" : "\\$26F-") + Time::Format(Math::Abs(deltaTime)) + "\\$z");
                }
            }
        }

        UI::EndTable();

        UI::EndGroup();

        UI::End();

    }
#endif
}

void RenderMenu() {
#if TMNEXT
    if(UI::MenuItem("\\$07f\\$s" + Icons::FighterJet + "\\$z COTD Stats Window", "", windowVisible)) {
        windowVisible = !windowVisible;
    }
#endif
}

void ReadHUD() {
	auto app = cast<CTrackMania>(GetApp());
    auto network = cast<CTrackManiaNetwork>(app.Network);
    auto server_info = cast<CTrackManiaNetworkServerInfo>(network.ServerInfo);

	while (true) {
		if (gameInfo.IsCotd()) {
            auto uilayers = network.ClientManiaAppPlayground.UILayers;
            for (uint i = 0; i < uilayers.Length; i++) {
                if (uilayers[i].LocalPage.MainFrame !is null) {
                    auto fs = uilayers[i].LocalPage.MainFrame.GetFirstChild("frame-score-owner");
                    if (fs !is null) {
                        auto tmp = cast<CControlFrame>(fs.Control);
                        string drank = cast<CControlLabel>(tmp.Childs[0]).Label;
                        string dname = cast<CControlLabel>(tmp.Childs[1]).Label;
                        string dtime = cast<CControlLabel>(tmp.Childs[2]).Label;
                        float irank = Text::ParseFloat(drank);
                        curdiv = uint(Math::Ceil(irank / 64.0f));

                        // hide next best until we have an actual div greater than 2
                        if (curdiv <= 2) {
                            nextdiv.hidden = true;
                        }
                        pb.div = "" + curdiv;
                        pb.time = Time::ParseRelativeTime(dtime);

                        // check if we have a new pb
                        flag_api_haveNewPb = pb.time != lastPb.time;
                        lastPb.time = pb.time;

                        if (curdiv > Text::ParseInt(lowerbounddiv.div) || pb.time > lowerbounddiv.time) {
                            lowerbounddiv.hidden = true;
                        }
                    }
                }
            }
        }
        divs.SortAsc();
		sleep(100);
	}
}

void Main() {
#if TMNEXT
    @gameInfo = GameInfo();

    // Use Co-routine to read HUD faster than API calls
    startnew(ReadHUD);

    startnew(UpdateFromAPI);
#endif
}


CTrackMania@ GetTmApp() {
    return cast<CTrackMania>(GetApp());
}

// todo: check if the div is full or not -- will get wrong times otherwise
void SetDivCutoff(CotdApi@ api, DivTime@&in divObj, int cid, string mid, int div) {
    // Only do this if div > 1 b/c we're already fetching div1 separately,
    if (div > 1) {
        // and don't request div cutoff times if the div isn't full
        if (div * 64 <= totalPlayers) {
            auto res = api.GetCutoffForDiv(cid, mid, div);
            divObj.time = (res.Length > 0) ? res[0]["time"] : 0;
        } else { // when the division isn't full
            divObj.time = MAX_DIV_TIME;
        }
        divObj.div = "" + div;
        divObj.hidden = false;
    } else {
        divObj.hidden = true;
    }
}

void UpdateFromAPI() {
    auto api = CotdApi();

    auto app = GetTmApp();
    auto network = cast<CTrackManiaNetwork>(app.Network);
    auto server_info = cast<CTrackManiaNetworkServerInfo>(network.ServerInfo);

    int challengeid = 0;

    // loop and sleep params/vars
    int msBetweenCalls = 15000;
    int sleepPerLoop = 100;

    // use loopCounter to only check API once every 15s
    int loopCounter = 0;
    int maxLoopCounter = msBetweenCalls / sleepPerLoop;

    // vars used every loop
    bool canCallAPI;
    bool checkThisLoop;
    bool hasPlayerId;
    string mapid;

    while (true) {
        canCallAPI = Permissions::PlayOnlineCompetition() && gameInfo.IsCotd();

        if (flag_api_haveNewPb) {
            loopCounter = 0;  // reset the counter to call the API now and also prevent us excessively calling the API
            flag_api_haveNewPb = false;
        }

        mapid = gameInfo.MapId();

        checkThisLoop = canCallAPI && mapid != "" && loopCounter == 0;

        if (checkThisLoop) {

            // trace("mapid:" + mapid);

            while (!NadeoServices::IsAuthenticated("NadeoClubServices")) {
                yield();
            }

            // We only need this info once at the beginning of the COTD
            if (challengeid == 0) {
                auto matchstatus = api.GetCotdStatus();
                string challengeName = matchstatus["challenge"]["name"];

                cotdName = "COTD " + challengeName.SubStr(15, 13);
                challengeid = matchstatus["challenge"]["id"];
            }

            // Use this to obtain "real-time" number of players registered in the COTD
            // (could've also used this to determine player rank and score, but for better experience we get those from HUD instead)
            auto rank = api.GetPlayersRank(challengeid, mapid, network.PlayerInfo.WebServicesUserId);
            totalPlayers = rank["cardinal"];

            // Fetch Div 1 cutoff record
            auto leadDiv1 = api.GetCutoffForDiv(challengeid, mapid, 1);
            if (leadDiv1.Length > 0) {
                div1.time = leadDiv1[0]["time"];
            }

            if (showLowerBound) {
                SetDivCutoff(api, lowerbounddiv, challengeid, mapid, curdiv);
            } else {
                lowerbounddiv.hidden = true;
            }

            SetDivCutoff(api, nextdiv, challengeid, mapid, curdiv - 1);

            if (showExtraDivs) {
                SetDivCutoff(api, nextnextdiv, challengeid, mapid, curdiv - 2);
                SetDivCutoff(api, belowdiv, challengeid, mapid, curdiv + 1);
            } else {
                nextnextdiv.hidden = true;
                belowdiv.hidden = true;
            }

        } else {
            if (!canCallAPI) {
                // Reset challenge id once COTD ends
                challengeid = 0;
            }
        }

        loopCounter = (loopCounter + 1) % maxLoopCounter;
        sleep(sleepPerLoop);
    }
}

Json::Value FetchEndpoint(const string &in route) {
    auto req = NadeoServices::Get("NadeoClubServices", route);
    req.Start();
    while(!req.Finished()) {
        yield();
    }
    return Json::Parse(req.String());
}

class CotdApi {
    string compUrl;
    CTrackMania@ app; // = GetTmApp();
    CTrackManiaNetwork@ network; // = cast<CTrackManiaNetwork>(app.Network);
    CTrackManiaNetworkServerInfo@ server_info; // = cast<CTrackManiaNetworkServerInfo>(network.ServerInfo);

    CotdApi() {
        NadeoServices::AddAudience("NadeoClubServices");
        compUrl = NadeoServices::BaseURLCompetition();

        @app = GetTmApp();
        @network = cast<CTrackManiaNetwork>(app.Network);
        @server_info = cast<CTrackManiaNetworkServerInfo>(network.ServerInfo);
    }

    Json::Value CallApiPath(string path) {
        if (path.Length <= 0 || !path.StartsWith("/")) {
            warn("[CallApiPath] API Paths should start with '/'!");
            path = "/" + path;
        }
        trace("Requesting: " + compUrl + path);
        return FetchEndpoint(compUrl + path);
    }

    Json::Value GetCotdStatus() {
        return CallApiPath("/api/daily-cup/current");
    }

    Json::Value GetCutoffForDiv(int challengeid, string mapid, int div) {
        // the last position in the div
        int offset = div * 64 - 1;
        return CallApiPath("/api/challenges/" + challengeid + "/records/maps/" + mapid + "?length=1&offset=" + offset);
    }

    Json::Value GetPlayersRank(int challengeid, string mapid, string userId) {
        return CallApiPath("/api/challenges/" + challengeid + "/records/maps/" + mapid + "/players?players[]=" + userId);
    }
}

class GameInfo {
    CTrackMania@ app; // = GetTmApp();
    // todo: these references might change -- refactor to getter functions or something
    CTrackManiaNetwork@ network; // = cast<CTrackManiaNetwork>(app.Network);
    CTrackManiaNetworkServerInfo@ server_info; // = cast<CTrackManiaNetworkServerInfo>(network.ServerInfo);

    GameInfo() {
        @app = GetTmApp();
        @network = cast<CTrackManiaNetwork>(app.Network);
        @server_info = cast<CTrackManiaNetworkServerInfo>(network.ServerInfo);
    }

    bool IsCotd() {
        return network.ClientManiaAppPlayground !is null
            && network.ClientManiaAppPlayground.Playground !is null
            && server_info.CurGameModeStr == "TM_TimeAttackDaily_Online";
    }

    string MapId() {
        auto rm = app.RootMap;
#if DEV
        int now = Time::get_Now();
        if ((now % 1000) < 100) {
            trace("[MapId()," + now + "] rm is null: " + (rm is null));
            if (rm !is null) {
                trace("[MapId()," + now + "] rm.IdName: " + rm.IdName);
            }
        }
#endif
        return (rm is null) ? "" : rm.IdName;
        // if (rm is null) {
        //     return "";
        // }
        // return rm.IdName;
    }
}

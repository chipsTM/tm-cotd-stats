[Setting category="Display Settings" name="Window visible" description="To move the table, click and drag while the Openplanet overlay is visible."]
bool windowVisible = true;

class DivTime {
    string div;
    int time;
    string style;
    bool hidden;

    DivTime(string div = "--", int time = 9999999, string style = "\\$fff", bool hidden = true) {
        this.div = div;
        this.time = time;
        this.style = style;
        this.hidden = hidden;
    }

    string DivString() {
        return this.style + ((this.div == "0") ? "--" : this.div) + "\\$z";
    }

    string TimeString() {
        return this.style + (((this.time > 0) && (this.time != 9999999)) ? Time::Format(this.time) : "-:--.---") + "\\$z";
    }

    int opCmp(DivTime@ other) {
        int diff = this.time - other.time;
        return (diff == 0) ? 0 : ((diff > 0) ? 1 : -1);
	}
}

// Global variables  
string cotdName = "";
int totalPlayers = 0;
int curdiv = 0;

DivTime@ div1 = DivTime("1", 0, "\\$fff", false);
DivTime@ nextdiv = DivTime("--", 9999999, "\\$fff");
DivTime@ pb = DivTime("--", 9999999, "\\$0ff", false);

array<DivTime@> divs = { pb, div1, nextdiv };

void Render() {
#if TMNEXT
    auto app = cast<CTrackMania>(GetApp());
    auto network = cast<CTrackManiaNetwork>(app.Network);
    auto server_info = cast<CTrackManiaNetworkServerInfo>(network.ServerInfo);

    if (windowVisible && app.CurrentPlayground !is null && server_info.CurGameModeStr == "TM_TimeAttackDaily_Online") {
    
        int windowFlags = UI::WindowFlags::NoTitleBar | UI::WindowFlags::NoCollapse | UI::WindowFlags::AlwaysAutoResize | UI::WindowFlags::NoDocking;

        if (!UI::IsOverlayShown()) {
            windowFlags |= UI::WindowFlags::NoInputs;
        }

        UI::Begin("COTD Qualifying", windowFlags);

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
        UI::Text("\\$aaa" + totalPlayers + " players\\$z");
        UI::EndTable();

        UI::BeginTable("ranking", 2, UI::TableFlags::SizingFixedFit);

        UI::TableNextRow();
        UI::TableNextColumn();
        UI::Text("Div");
        UI::TableNextColumn();
        UI::Text("Cutoff");

        for(uint i = 0; i < divs.Length; i++) {
            if(divs[i].hidden) {
                continue;
            }
            UI::TableNextRow();
            UI::TableNextColumn();
            UI::Text(divs[i].DivString());
            UI::TableNextColumn();
            UI::Text(divs[i].TimeString());
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

Json::Value FetchEndpoint(const string &in route) {
    auto req = NadeoServices::Get("NadeoClubServices", route);
    req.Start();
    while(!req.Finished()) {
        yield();
    }
    return Json::Parse(req.String());
}

void ReadHUD() {
	auto app = cast<CTrackMania>(GetApp());
    auto network = cast<CTrackManiaNetwork>(app.Network);
    auto server_info = cast<CTrackManiaNetworkServerInfo>(network.ServerInfo);

	while (true) {
		if (network.ClientManiaAppPlayground !is null && network.ClientManiaAppPlayground.Playground !is null && server_info.CurGameModeStr == "TM_TimeAttackDaily_Online") {
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
                    }
                }
            }
        }
        divs.SortAsc();
		sleep(500);
	}
}

void Main() {
#if TMNEXT
    auto app = cast<CTrackMania>(GetApp());
    auto network = cast<CTrackManiaNetwork>(app.Network);
    auto server_info = cast<CTrackManiaNetworkServerInfo>(network.ServerInfo);
    
    NadeoServices::AddAudience("NadeoClubServices");
    string compUrl = NadeoServices::BaseURLCompetition();

    // Use Co-routine to read HUD faster than API calls
    startnew(ReadHUD);

    int challengeid = 0;

    while(true) {

        if (Permissions::PlayOnlineCompetition() && network.ClientManiaAppPlayground !is null && network.ClientManiaAppPlayground.Playground !is null && network.ClientManiaAppPlayground.Playground.Map !is null && server_info.CurGameModeStr == "TM_TimeAttackDaily_Online") {
            
            string mapid = network.ClientManiaAppPlayground.Playground.Map.MapInfo.MapUid;

            while (!NadeoServices::IsAuthenticated("NadeoClubServices")) {
                yield();
            }

            // We only need this info once at the beginning of the COTD
            if (challengeid == 0) {
                auto matchstatus = FetchEndpoint(compUrl + "/api/daily-cup/current");
                string challengeName = matchstatus["challenge"]["name"];

                cotdName = "COTD " + challengeName.SubStr(15, 13);
                challengeid = matchstatus["challenge"]["id"];
            }

            // Use this to obtain "real-time" number of players registered in the COTD 
            // (could've also used this to determine player rank and score, but for better experience we get those from HUD instead)
            auto rank = FetchEndpoint(compUrl + "/api/challenges/" + challengeid + "/records/maps/" + mapid + "/players?players[]=" + network.PlayerInfo.WebServicesUserId);
            totalPlayers = rank["cardinal"];

            // Fetch Div 1 cutoff record
            auto leadDiv1 = FetchEndpoint(compUrl + "/api/challenges/" + challengeid + "/records/maps/" + mapid + "?length=1&offset=63");
            if (leadDiv1.Length > 0) {
                div1.time = leadDiv1[0]["time"];
            }

            // Fetch next best Div cutoff record only if we are higher than Div 2
            if (curdiv > 2) {
                auto leadNextBest = FetchEndpoint(compUrl + "/api/challenges/" + challengeid + "/records/maps/" + mapid + "?length=1&offset=" + (64 * (curdiv - 1) - 1));
                if (leadNextBest.Length > 0) {
                    nextdiv.time = leadNextBest[0]["time"];
                }
                nextdiv.div = "" + (curdiv-1);
                nextdiv.hidden = false;
            } else {
                nextdiv.hidden = true;
            }

        } else {
            // Reset challenge id once COTD ends
            challengeid = 0;
        }
        sleep(15000);
    }
#endif
}
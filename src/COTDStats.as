[Setting category="Display Settings" name="Window visible" description="To move the table, click and drag while the Openplanet overlay is visible"]
bool windowVisible = true;

[Setting category="Display Settings" name="Hide when game UI is hidden"]
bool hideWithGame = true;

[Setting category="Display Settings" name="Hide when Openplanet UI is hidden"]
bool hideWithOP = false;

[Setting category="Display Settings" name="Only show when in qualifier" description="When disabled, this will still show when you leave the qualifier and rejoin in standard Time Attack"]
bool showOnlyDuringQuali = true;

[Setting category="Display Settings" name="Show competition name" description="Shows date and COTD number at the top of the window"]
bool showCompName = true;

[Setting category="Display Settings" name="Show number of players and divisions"]
bool showPlayerDivCount = true;

[Setting category="Display Settings" name="Show Div Delta" description="Shows your delta time for the different divisions"]
bool showDivDelta = false;

[Setting category="Display Settings" name="Show lower bound" description="Disabled by default"]
bool showLowerBound = false;

class DivTime {
    string div;
    int time;
    string style;
    bool hidden;

    DivTime(const string &in div = "--", int time = 9999999, const string &in style = "\\$fff", bool hidden = true) {
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
DivTime@ lowerbounddiv = DivTime("--", 9999999, "\\$fff", !showLowerBound);
DivTime@ pb = DivTime("--", 9999999, "\\$0ff", false);

array<DivTime@> divs = { pb, div1, nextdiv, lowerbounddiv };

void Render() {
#if TMNEXT
    if ((hideWithGame && !UI::IsGameUIVisible()) || (hideWithOP && !UI::IsOverlayShown()))
        return;

    auto app = cast<CTrackMania>(GetApp());
    auto network = cast<CTrackManiaNetwork>(app.Network);
    auto server_info = cast<CTrackManiaNetworkServerInfo>(network.ServerInfo);

    if (
        windowVisible &&
        app.CurrentPlayground !is null &&
        (server_info.CurGameModeStr == "TM_COTDQualifications_Online" || (!showOnlyDuringQuali && server_info.CurGameModeStr == "TM_TimeAttackDaily_Online"))
    ) {
        int windowFlags = UI::WindowFlags::NoTitleBar | UI::WindowFlags::NoCollapse | UI::WindowFlags::AlwaysAutoResize | UI::WindowFlags::NoDocking;

        if (!UI::IsOverlayShown()) {
            windowFlags |= UI::WindowFlags::NoInputs;
        }

        UI::Begin("COTD Qualifying", windowFlags);

        UI::PushStyleVar(UI::StyleVar::ItemSpacing, vec2(0, 0));
        UI::Dummy(vec2(0, 0));
        UI::PopStyleVar();

        UI::BeginGroup();

        if (showCompName || showPlayerDivCount) {
            UI::BeginTable("header", 1, UI::TableFlags::SizingFixedFit);
            if (showCompName) {
                UI::TableNextRow();
                UI::TableNextColumn();
                UI::Text(cotdName);
            }
            if (showPlayerDivCount) {
                UI::TableNextRow();
                UI::TableNextColumn();
                UI::Text("\\$aaa" + totalPlayers + " players (" + Math::Ceil(totalPlayers/64.0) + " divs)\\$z");
            }
            UI::EndTable();
        }

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
                if (deltaTime != 0 && pb.time != 9999999 && divs[i].time != 9999999) {
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

Json::Value@ FetchNadeoEndpoint(const string &in route) {
    auto req = NadeoServices::Get("NadeoClubServices", route);
    req.Start();
    while(!req.Finished()) {
        yield();
    }
    return Json::Parse(req.String());
}

Json::Value@ FetchMonitorEndpoint(const string &in route) {
    auto req = Net::HttpGet(route);
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
        if (
            network.ClientManiaAppPlayground !is null &&
            network.ClientManiaAppPlayground.Playground !is null &&
            (server_info.CurGameModeStr == "TM_COTDQualifications_Online" || (!showOnlyDuringQuali && server_info.CurGameModeStr == "TM_TimeAttackDaily_Online"))
        ) {
            auto uilayers = network.ClientManiaAppPlayground.UILayers;
            for (uint i = 0; i < uilayers.Length; i++) {
                if (uilayers[i].LocalPage.MainFrame !is null) {
                    string drank;
                    string dname;
                    string dtime;
                    auto scoreOwner = uilayers[i].LocalPage.MainFrame.GetFirstChild("frame-score-owner");
                    if (scoreOwner is null) {
                        continue;
                    }

                    auto lrank = cast<CGameManialinkFrame@>(scoreOwner).GetFirstChild("label-rank");
                    if (lrank !is null) {
                        drank = cast<CControlLabel>(lrank.Control).Label;
                        float irank = Text::ParseFloat(drank);
                        curdiv = uint(Math::Ceil(irank / 64.0f));
                        pb.div = "" + curdiv;
                    }
                    // auto lname = uilayers[i].LocalPage.MainFrame.GetFirstChild("label-name");
                    // if (lname !is null) {
                    //     dname = cast<CControlLabel>(lname.Control).Label;
                    // }
                    auto ltime = cast<CGameManialinkFrame@>(scoreOwner).GetFirstChild("label-time");
                    if (ltime !is null) {
                        dtime = cast<CControlLabel>(ltime.Control).Label;
                        pb.time = Time::ParseRelativeTime(dtime);
                    }
                    // string drank = cast<CControlLabel>(tmp.Childs[2]).Label;
                    // string dname = cast<CControlLabel>(tmp.Childs[3]).Label;
                    // string dtime = cast<CControlLabel>(tmp.Childs[4]).Label;

                    // hide next best until we have an actual div greater than 2
                    if (curdiv <= 2) {
                        nextdiv.hidden = true;
                    }

                    if (curdiv > Text::ParseInt(lowerbounddiv.div) || pb.time > lowerbounddiv.time) {
                        lowerbounddiv.hidden = true;
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
    string monitorUrl = "https://map-monitor.xk.io/cached";

    // Use Co-routine to read HUD faster than API calls
    startnew(ReadHUD);

    int challengeid = 0;

    while(true) {
        if (
            Permissions::PlayOnlineCompetition() &&
            network.ClientManiaAppPlayground !is null &&
            network.ClientManiaAppPlayground.Playground !is null &&
            network.ClientManiaAppPlayground.Playground.Map !is null &&
            (server_info.CurGameModeStr == "TM_COTDQualifications_Online" || (!showOnlyDuringQuali && server_info.CurGameModeStr == "TM_TimeAttackDaily_Online"))
        ) {
            string mapid = network.ClientManiaAppPlayground.Playground.Map.MapInfo.MapUid;

            while (!NadeoServices::IsAuthenticated("NadeoClubServices")) {
                yield();
            }

            // We only need this info once at the beginning of the COTD
            if (challengeid == 0) {
                auto matchstatus = FetchMonitorEndpoint(monitorUrl + "/api/cup-of-the-day/current");
                if (matchstatus !is null && matchstatus.GetType() == Json::Type::Object && matchstatus.HasKey("challenge") && matchstatus.HasKey("competition")) {
                    cotdName = matchstatus["competition"]["name"];
                    challengeid = matchstatus["challenge"]["id"];
                } else {
                    trace("Failed to get current cup details, retrying...");
                }
            }

            // Use this to obtain "real-time" number of players registered in the COTD
            // (could've also used this to determine player rank and score, but for better experience we get those from HUD instead)
            auto rank = FetchMonitorEndpoint(monitorUrl + "/api/challenges/" + challengeid + "/records/maps/" + mapid + "/players?players[]=" + network.PlayerInfo.WebServicesUserId);
            if (rank.GetType() == Json::Type::Object && rank.HasKey("cardinal")) {
                totalPlayers = rank["cardinal"];
            }

            // Fetch Div 1 cutoff record
            auto leadDiv1 = FetchMonitorEndpoint(monitorUrl + "/api/challenges/" + challengeid + "/records/maps/" + mapid + "?length=1&offset=63");
            if (leadDiv1.GetType() == Json::Type::Array && leadDiv1.Length > 0) {
                div1.time = leadDiv1[0]["time"];
            } else if (leadDiv1.GetType() == Json::Type::Object && leadDiv1['json_payload'].Length > 0) {
                div1.time = leadDiv1['json_payload'][0]["time"];
            }

            if (showLowerBound && curdiv > 1) {
                auto lowerBound = FetchMonitorEndpoint(monitorUrl + "/api/challenges/" + challengeid + "/records/maps/" + mapid + "?length=1&offset=" + (64 * (curdiv) - 1));
                if (lowerBound.GetType() == Json::Type::Array && lowerBound.Length > 0) {
                    lowerbounddiv.time = lowerBound[0]["time"];
                } else if (lowerBound.GetType() == Json::Type::Object && lowerBound['json_payload'].Length > 0) {
                    lowerbounddiv.time = lowerBound['json_payload'][0]["time"];
                }
                lowerbounddiv.div = "" + curdiv;
                lowerbounddiv.hidden = false;
            } else {
                lowerbounddiv.hidden = true;
            }

            // Fetch next best Div cutoff record only if we are higher than Div 2
            if (curdiv > 2) {
                auto leadNextBest = FetchMonitorEndpoint(monitorUrl + "/api/challenges/" + challengeid + "/records/maps/" + mapid + "?length=1&offset=" + (64 * (curdiv - 1) - 1));
                if (leadNextBest.GetType() == Json::Type::Array && leadNextBest.Length > 0) {
                    nextdiv.time = leadNextBest[0]["time"];
                } else if (leadNextBest.GetType() == Json::Type::Object && leadNextBest['json_payload'].Length > 0) {
                    nextdiv.time = leadNextBest['json_payload'][0]["time"];
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
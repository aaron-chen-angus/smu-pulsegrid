# =============================================================================
# SMU//PULSE//GRID — R Shiny Analytics Dashboard  (TRON theme)
# Reads the live Google Sheet (3 tabs) via the public CSV export endpoint, and
# renders all charts with ggplot2 (NOT plotly) to avoid the htmlwidgets/plotly
# "is.character(txt) is not TRUE" dependency error seen on Posit Cloud.
#
# SETUP (run once):
#   install.packages(c("shiny","shinydashboard","dplyr","tidyr","ggplot2",
#                      "DT","lubridate","readr","scales"))
# RUN:    shiny::runApp("shiny")      # or whatever folder holds this app.R
# DEPLOY: rsconnect::deployApp("shiny")
# =============================================================================

library(shiny)
library(shinydashboard)
library(dplyr)
library(tidyr)
library(ggplot2)
library(DT)
library(lubridate)
library(readr)
library(scales)

# --- Config ------------------------------------------------------------------
SHEET_ID <- "1iYSFfDxljE1kT8cqAjHRvG2QVQ0374ZQRY-_e7cL_k8"
REFRESH_SECONDS <- 60
EMO_COLS <- c("neutral","happy","sad","angry","fearful","disgusted","surprised")

CYAN <- "#00E5FF"; ORANGE <- "#FF8A00"; OK <- "#3DFFB0"; ALERT <- "#FF3B5C"
BG <- "#05070D"; PANEL <- "#0b1420"; INK <- "#eaffff"; MUTE <- "#7fa6c0"

csv_url <- function(tab) paste0(
  "https://docs.google.com/spreadsheets/d/", SHEET_ID,
  "/gviz/tq?tqx=out:csv&sheet=", utils::URLencode(tab))

read_tab <- function(tab) {
  df <- tryCatch(
    suppressWarnings(readr::read_csv(csv_url(tab), show_col_types = FALSE,
                                     col_types = cols(.default = col_character()))),
    error = function(e) NULL)
  if (is.null(df) || !nrow(df)) return(data.frame())
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  df[] <- lapply(df, function(col) as.character(unlist(col, use.names = FALSE)))
  df
}
n_ <- function(x) suppressWarnings(as.numeric(x))
as_bool <- function(x) tolower(trimws(as.character(x))) %in% c("true","1","yes")

load_all <- function() {
  sessions <- read_tab("Sessions"); emotions <- read_tab("EmotionScans"); timeline <- read_tab("IntensityTimeline")
  if (nrow(sessions)) {
    for (c in c("match_distance","duration_s","active_pct","kcal","met_mean","upper_avg","upper_peak",
                "upper_effort_pct","lower_avg","lower_peak","lower_effort_pct","overall_avg",
                "match_pct","sync_score","zone_pct","weight_kg"))
      if (c %in% names(sessions)) sessions[[c]] <- n_(sessions[[c]])
    if ("sign_in_at" %in% names(sessions))
      sessions$sign_in_dt <- suppressWarnings(ymd_hms(sessions$sign_in_at, quiet = TRUE))
  }
  if (nrow(emotions)) for (c in c(EMO_COLS,"valence","arousal","neg_affect","frames"))
    if (c %in% names(emotions)) emotions[[c]] <- n_(emotions[[c]])
  if (nrow(timeline)) for (c in c("t_s","user_upper","user_lower","user_overall",
                                  "ref_upper","ref_lower","ref_overall","match_pct"))
    if (c %in% names(timeline)) timeline[[c]] <- n_(timeline[[c]])
  list(sessions = sessions, emotions = emotions, timeline = timeline)
}

# --- TRON ggplot theme -------------------------------------------------------
theme_tron <- function() {
  theme_minimal(base_size = 13) +
    theme(
      plot.background  = element_rect(fill = PANEL, colour = NA),
      panel.background = element_rect(fill = PANEL, colour = NA),
      panel.grid.major = element_line(colour = "#13202e", linewidth = 0.3),
      panel.grid.minor = element_blank(),
      text  = element_text(colour = INK),
      axis.text = element_text(colour = MUTE, size = 11),
      axis.title = element_text(colour = MUTE, size = 12),
      axis.ticks = element_blank(),
      legend.text = element_text(colour = MUTE),
      legend.title = element_blank(),
      legend.position = "top",
      legend.background = element_rect(fill = PANEL, colour = NA),
      legend.key = element_rect(fill = PANEL, colour = NA),
      plot.title = element_text(colour = INK, family = "sans", face = "bold"),
      plot.margin = margin(14, 16, 10, 12)
    )
}
# Kept for backward compat with the per-plot calls; grid colour now lives in theme_tron().
tron_grid <- theme(panel.grid.major = element_line(colour = "#13202e", linewidth = 0.3))

emptyplot <- function(msg) ggplot() +
  annotate("text", 0, 0.15, label = "// NO DATA", colour = CYAN, size = 6,
           fontface = "bold", family = "sans") +
  annotate("text", 0, -0.15, label = msg, colour = MUTE, size = 4.5) +
  ylim(-1, 1) +
  theme_void() + theme(plot.background  = element_rect(fill = PANEL, colour = NA),
                       panel.background = element_rect(fill = PANEL, colour = NA))

# Neon label helper for bars (glow-ish white text sitting just above/beside bars)
lab_num <- function(x, pct = FALSE, dp = 0) {
  if (pct) sprintf(paste0("%.", dp, "f%%"), x) else formatC(x, format = "f", digits = dp, big.mark = ",")
}

# =============================================================================
# UI
# =============================================================================
tron_css <- HTML(sprintf("
  @import url('https://fonts.googleapis.com/css2?family=Orbitron:wght@600;700;800&family=Rajdhani:wght@500;600&display=swap');
  body,.content-wrapper,.right-side{background:%s !important;
    background-image:linear-gradient(rgba(0,229,255,0.045) 1px,transparent 1px),
      linear-gradient(90deg,rgba(0,229,255,0.045) 1px,transparent 1px);
    background-size:40px 40px;color:%s;font-family:'Rajdhani',sans-serif;}
  /* Wider logo area so SMU//PULSE//GRID is never cut off */
  .skin-black .main-header .logo{width:260px;background:%s !important;color:%s !important;
    font-family:'Orbitron',sans-serif;font-weight:800;font-size:16px;letter-spacing:0.04em;
    text-shadow:0 0 12px %s;border-bottom:1px solid rgba(0,229,255,0.3);
    white-space:nowrap;overflow:hidden;}
  .skin-black .main-header .navbar{background:%s !important;margin-left:260px;}
  .skin-black .main-header .sidebar-toggle{color:%s !important;}
  @media (max-width:767px){ .skin-black .main-header .logo{width:100%%;} .skin-black .main-header .navbar{margin-left:0;} }
  .main-sidebar,.skin-black .main-sidebar{background:#070b12 !important;border-right:1px solid rgba(0,229,255,0.2);width:260px;}
  .content-wrapper,.main-footer{margin-left:260px;}
  @media (max-width:767px){ .content-wrapper{margin-left:0;} }
  .sidebar-menu>li>a{color:%s !important;font-family:'Orbitron',sans-serif;font-size:13px;}
  .sidebar-menu>li.active>a,.sidebar-menu>li>a:hover{color:%s !important;
    border-left:3px solid %s !important;background:rgba(0,229,255,0.06) !important;}
  .box{background:%s !important;border:1px solid rgba(0,229,255,0.3) !important;
    border-top:3px solid %s !important;border-radius:3px;box-shadow:inset 0 0 24px rgba(0,229,255,0.05);}
  .box-header .box-title{font-family:'Orbitron',sans-serif;font-size:13px;letter-spacing:0.2em;
    text-transform:uppercase;color:%s;}
  h1,h2,h3,h4{color:%s;font-family:'Orbitron',sans-serif;}
  .small-box h3{font-family:'Orbitron',sans-serif;font-weight:800;}
  .btn{font-family:'Orbitron',sans-serif;letter-spacing:0.06em;}
  .form-control,.selectize-input,.selectize-dropdown{background:#0a121c !important;color:%s !important;
    border:1px solid rgba(0,229,255,0.3) !important;}
  table.dataTable tbody tr{background:%s !important;color:%s !important;}
  .dataTables_wrapper{color:%s !important;}
", BG, INK, BG, CYAN, CYAN, BG, CYAN, MUTE, CYAN, CYAN, PANEL, CYAN, INK, INK, INK, PANEL, INK, MUTE))

ui <- dashboardPage(skin = "black",
  dashboardHeader(title = HTML("SMU<span style='color:#FF8A00'>//</span>PULSE<span style='color:#FF8A00'>//</span>GRID"),
                  titleWidth = 260),
  dashboardSidebar(width = 260,
    sidebarMenu(
      menuItem("Overview", tabName = "overview", icon = icon("gauge")),
      menuItem("Session drill-down", tabName = "session", icon = icon("person-running")),
      menuItem("Emotion & stress", tabName = "emotion", icon = icon("face-smile")),
      menuItem("Cohort analytics", tabName = "cohort", icon = icon("chart-line")),
      menuItem("Raw data", tabName = "raw", icon = icon("table"))),
    actionButton("refresh", "Refresh now", icon = icon("rotate"), style = "margin:10px;"),
    div(style = "color:#7fa6c0;font-size:12px;padding:0 12px;", textOutput("last_refresh"))),
  dashboardBody(
    tags$head(tags$style(tron_css)),
    tabItems(
      tabItem("overview",
        fluidRow(valueBoxOutput("vb_sessions",3), valueBoxOutput("vb_people",3),
                 valueBoxOutput("vb_match",3), valueBoxOutput("vb_kcal",3)),
        fluidRow(
          box(title="Sessions over time", width=8, solidHeader=TRUE, plotOutput("p_sessions_time", height=300)),
          box(title="Completion", width=4, solidHeader=TRUE, plotOutput("p_completion", height=300))),
        fluidRow(
          box(title="Match % distribution", width=6, solidHeader=TRUE, plotOutput("p_match_dist", height=280)),
          box(title="Upper vs Lower effort (vs instructor)", width=6, solidHeader=TRUE, plotOutput("p_effort", height=280)))),
      tabItem("session",
        fluidRow(box(width=12, solidHeader=TRUE, title="Select a session",
                     selectInput("sel_session", NULL, choices=NULL, width="60%"))),
        fluidRow(valueBoxOutput("sb_dur",3), valueBoxOutput("sb_kcal",3),
                 valueBoxOutput("sb_match",3), valueBoxOutput("sb_sync",3)),
        fluidRow(box(title="Intensity timeline — you vs instructor", width=12, solidHeader=TRUE, plotOutput("p_timeline", height=360))),
        fluidRow(
          box(title="Emotion — Sign In vs Sign Out", width=6, solidHeader=TRUE, plotOutput("p_emo_inout", height=360)),
          box(title="Emotion change (Out - In)", width=6, solidHeader=TRUE, plotOutput("p_delta", height=360)))),
      tabItem("emotion",
        fluidRow(
          box(title="Stress level: Sign In vs Sign Out", width=6, solidHeader=TRUE, plotOutput("p_stress", height=320)),
          box(title="Valence change (In -> Out)", width=6, solidHeader=TRUE, plotOutput("p_valence", height=320))),
        fluidRow(box(title="Mean emotion profile (all scans)", width=12, solidHeader=TRUE, plotOutput("p_emo_profile", height=320)))),
      tabItem("cohort",
        fluidRow(
          box(title="Match % vs Sync score", width=6, solidHeader=TRUE, plotOutput("p_scatter", height=340)),
          box(title="Average Match % per person", width=6, solidHeader=TRUE, plotOutput("p_person", height=340))),
        fluidRow(box(title="Correlation of session metrics", width=12, solidHeader=TRUE, plotOutput("p_corr", height=420)))),
      tabItem("raw",
        tabsetPanel(
          tabPanel("Sessions", DTOutput("dt_sessions")),
          tabPanel("EmotionScans", DTOutput("dt_emotions")),
          tabPanel("IntensityTimeline", DTOutput("dt_timeline")))))))

# =============================================================================
# SERVER
# =============================================================================
server <- function(input, output, session) {
  rv <- reactiveVal(load_all())
  observe({ invalidateLater(REFRESH_SECONDS*1000, session); rv(load_all()) })
  observeEvent(input$refresh, { rv(load_all()) })
  output$last_refresh <- renderText(paste("Updated:", format(Sys.time(), "%H:%M:%S")))

  sessions <- reactive(rv()$sessions); emotions <- reactive(rv()$emotions); timeline <- reactive(rv()$timeline)

  observe({
    s <- sessions()
    if (nrow(s) && "session_id" %in% names(s)) {
      labels <- if ("name" %in% names(s)) paste0(s$name, "  (", s$session_id, ")") else s$session_id
      updateSelectInput(session, "sel_session", choices = setNames(s$session_id, labels))
    }
  })

  vbx <- function(v, sub, ic, col) valueBox(v, sub, icon = icon(ic), color = col)
  output$vb_sessions <- renderValueBox(vbx(nrow(sessions()), "Sessions", "list", "aqua"))
  output$vb_people   <- renderValueBox(vbx(if ("name" %in% names(sessions())) length(unique(sessions()$name)) else 0, "Unique people", "users", "teal"))
  output$vb_match    <- renderValueBox({ v <- if ("match_pct" %in% names(sessions())) round(mean(sessions()$match_pct, na.rm=TRUE)) else NA
    vbx(ifelse(is.na(v),"—",paste0(v,"%")), "Avg Match", "bullseye", "green") })
  output$vb_kcal     <- renderValueBox({ v <- if ("kcal" %in% names(sessions())) round(sum(sessions()$kcal, na.rm=TRUE),1) else 0
    vbx(v, "Total kcal", "fire", "orange") })

  output$p_sessions_time <- renderPlot(bg = PANEL, {
    s <- sessions(); if (!nrow(s) || !"sign_in_dt" %in% names(s)) return(emptyplot("No sessions yet"))
    d <- s %>% filter(!is.na(sign_in_dt)) %>% mutate(day = as.Date(sign_in_dt)) %>% count(day)
    if (!nrow(d)) return(emptyplot("No dated sessions"))
    ggplot(d, aes(day, n)) +
      geom_area(fill = CYAN, alpha = 0.12) +
      geom_line(colour = CYAN, linewidth = 1) +
      geom_point(colour = CYAN, fill = BG, shape = 21, size = 3, stroke = 1.2) +
      geom_text(aes(label = n), vjust = -1, colour = INK, size = 4, fontface = "bold") +
      scale_y_continuous(expand = expansion(mult = c(0, 0.18))) +
      labs(x = NULL, y = "Sessions") + theme_tron() + tron_grid
  })
  output$p_completion <- renderPlot(bg = PANEL, {
    s <- sessions(); if (!nrow(s) || !"completed" %in% names(s)) return(emptyplot("No sessions yet"))
    d <- s %>% mutate(c = as_bool(completed)) %>% count(c) %>%
      mutate(lbl = ifelse(c,"Completed","Ended early"), pct = n / sum(n))
    tot <- sum(d$n); comp <- round(100 * sum(d$n[d$c]) / tot)
    ggplot(d, aes(x = 2, y = n, fill = lbl)) +
      geom_col(width = 1, colour = PANEL, linewidth = 1.5) +
      coord_polar("y") + xlim(0.3, 2.5) +
      annotate("text", x = 0.3, y = 0, label = paste0(comp, "%"),
               colour = OK, size = 11, fontface = "bold", family = "sans") +
      annotate("text", x = 0.3, y = 0, label = "", colour = MUTE) +
      scale_fill_manual(values = c("Completed"=OK, "Ended early"=ORANGE)) +
      theme_void() + theme(plot.background  = element_rect(fill = PANEL, colour = NA),
                           panel.background = element_rect(fill = PANEL, colour = NA),
                           legend.position = "bottom",
                           legend.background = element_rect(fill = PANEL, colour = NA),
                           legend.key = element_rect(fill = PANEL, colour = NA),
                           legend.text = element_text(colour = MUTE), legend.title = element_blank())
  })
  output$p_match_dist <- renderPlot(bg = PANEL, {
    s <- sessions(); if (!"match_pct" %in% names(s) || !any(!is.na(s$match_pct))) return(emptyplot("No match data"))
    m <- s$match_pct[!is.na(s$match_pct)]
    ggplot(data.frame(m = m), aes(m)) +
      geom_histogram(bins = 20, fill = CYAN, colour = PANEL, linewidth = 0.6, alpha = 0.9) +
      geom_vline(xintercept = mean(m), colour = ORANGE, linewidth = 1, linetype = "dashed") +
      annotate("text", x = mean(m), y = Inf, label = paste0(" mean ", round(mean(m)), "%"),
               colour = ORANGE, hjust = 0, vjust = 1.6, size = 4, fontface = "bold") +
      scale_y_continuous(expand = expansion(mult = c(0, 0.1))) +
      labs(x = "Match %", y = "Count") + theme_tron() + tron_grid
  })
  output$p_effort <- renderPlot(bg = PANEL, {
    s <- sessions(); if (!all(c("upper_effort_pct","lower_effort_pct") %in% names(s))) return(emptyplot("No effort data"))
    nm <- if ("name" %in% names(s)) s$name else s$session_id
    d <- data.frame(name = nm, Upper = s$upper_effort_pct, Lower = s$lower_effort_pct) %>%
      pivot_longer(c(Upper, Lower), names_to = "group", values_to = "effort")
    ggplot(d, aes(name, effort, fill = group)) +
      geom_col(position = position_dodge(0.8), width = 0.72) +
      geom_hline(yintercept = 100, colour = MUTE, linetype = "dotted", linewidth = 0.5) +
      scale_fill_manual(values = c("Upper"=CYAN, "Lower"=ORANGE)) +
      scale_y_continuous(expand = expansion(mult = c(0, 0.08))) +
      labs(x = NULL, y = "Effort % vs instructor") +
      theme_tron() + tron_grid + theme(axis.text.x = element_text(angle = 30, hjust = 1))
  })

  cur <- reactive({ s <- sessions(); req(input$sel_session); s[s$session_id == input$sel_session,,drop=FALSE] })
  output$sb_dur  <- renderValueBox({ r <- cur(); v <- if (nrow(r)) r$duration_s[1] else NA
    vbx(ifelse(is.na(v),"—",sprintf("%d:%02d", v%/%60, round(v%%60))), "Duration", "clock", "aqua") })
  output$sb_kcal <- renderValueBox({ r <- cur(); vbx(ifelse(nrow(r), r$kcal[1], "—"), "kcal", "fire", "orange") })
  output$sb_match<- renderValueBox({ r <- cur(); vbx(ifelse(nrow(r) && !is.na(r$match_pct[1]), paste0(round(r$match_pct[1]),"%"), "—"), "Match", "bullseye", "green") })
  output$sb_sync <- renderValueBox({ r <- cur(); vbx(ifelse(nrow(r) && !is.na(r$sync_score[1]), round(r$sync_score[1]), "—"), "Sync", "wave-square", "teal") })

  output$p_timeline <- renderPlot(bg = PANEL, {
    t <- timeline(); if (is.null(input$sel_session)) return(emptyplot("Select a session"))
    d <- t[t$session_id == input$sel_session,,drop=FALSE]
    if (nrow(d) < 2) return(emptyplot("No timeline for this session"))
    dl <- d %>% select(t_s, user_upper, user_lower, ref_overall) %>%
      pivot_longer(-t_s, names_to = "series", values_to = "v")
    ggplot(dl, aes(t_s, v, colour = series)) + geom_line(linewidth = 0.9) +
      scale_colour_manual(values = c(user_upper=CYAN, user_lower=ORANGE, ref_overall="#b9c6d2"),
                          labels = c("You · upper","You · lower","Instructor")) +
      labs(x = "Time (s)", y = "Intensity (0-100)") + theme_tron() + tron_grid
  })

  emo_cur <- reactive({ e <- emotions(); req(input$sel_session); e[e$session_id == input$sel_session,,drop=FALSE] })
  output$p_emo_inout <- renderPlot(bg = PANEL, {
    e <- emo_cur(); if (!nrow(e)) return(emptyplot("No emotion scans"))
    rows <- lapply(c("in","out"), function(ph){
      r <- e[e$phase==ph,,drop=FALSE]; if (!nrow(r)) return(NULL)
      data.frame(phase = ph, emotion = EMO_COLS, val = as.numeric(r[1, EMO_COLS]))
    })
    d <- do.call(rbind, rows); if (is.null(d)) return(emptyplot("No scans"))
    ggplot(d, aes(emotion, val, fill = phase)) + geom_col(position = "dodge") +
      scale_fill_manual(values = c("in"=CYAN, "out"=ORANGE), labels = c("Sign In","Sign Out")) +
      labs(x = NULL, y = "Mean probability") + theme_tron() + tron_grid +
      theme(axis.text.x = element_text(angle = 30, hjust = 1))
  })
  output$p_delta <- renderPlot(bg = PANEL, {
    e <- emo_cur(); ein <- e[e$phase=="in", EMO_COLS, drop=FALSE]; eout <- e[e$phase=="out", EMO_COLS, drop=FALSE]
    if (!nrow(ein) || !nrow(eout)) return(emptyplot("Need both scans"))
    d <- data.frame(emotion = EMO_COLS, delta = as.numeric(eout[1,]) - as.numeric(ein[1,]))
    ggplot(d, aes(emotion, delta, fill = delta >= 0)) + geom_col() +
      scale_fill_manual(values = c("TRUE"=ORANGE, "FALSE"=CYAN), guide = "none") +
      labs(x = NULL, y = "Out - In") + theme_tron() + tron_grid +
      theme(axis.text.x = element_text(angle = 30, hjust = 1))
  })

  output$p_stress <- renderPlot(bg = PANEL, {
    e <- emotions(); if (!"stress_level" %in% names(e) || !nrow(e)) return(emptyplot("No stress data"))
    d <- e %>% count(phase, stress_level)
    ggplot(d, aes(phase, n, fill = stress_level)) + geom_col() +
      scale_fill_manual(values = c("Normal"=OK, "Elevated"=ORANGE, "High"=ALERT)) +
      labs(x = NULL, y = "Scans") + theme_tron() + tron_grid
  })
  output$p_valence <- renderPlot(bg = PANEL, {
    e <- emotions(); if (!all(c("valence","phase","session_id") %in% names(e))) return(emptyplot("No valence data"))
    w <- e %>% select(session_id, phase, valence) %>% pivot_wider(names_from = phase, values_from = valence)
    if (!all(c("in","out") %in% names(w))) return(emptyplot("Need in & out scans"))
    w <- w %>% filter(!is.na(`in`) & !is.na(out)) %>% mutate(change = out - `in`)
    if (!nrow(w)) return(emptyplot("Need in & out scans"))
    ggplot(w, aes(session_id, change, fill = change >= 0)) + geom_col() +
      scale_fill_manual(values = c("TRUE"=OK, "FALSE"=ALERT), guide = "none") +
      labs(x = NULL, y = "Valence change") + theme_tron() + tron_grid +
      theme(axis.text.x = element_text(angle = 40, hjust = 1, size = 8))
  })
  output$p_emo_profile <- renderPlot(bg = PANEL, {
    e <- emotions(); if (!nrow(e)) return(emptyplot("No emotion data"))
    m <- data.frame(emotion = EMO_COLS, v = sapply(EMO_COLS, function(c) mean(e[[c]], na.rm=TRUE)))
    m <- m[order(-m$v), ]; m$emotion <- factor(m$emotion, levels = m$emotion)
    ggplot(m, aes(emotion, v, fill = v)) +
      geom_col(width = 0.68) +
      geom_text(aes(label = lab_num(100*v, pct = TRUE)), vjust = -0.6,
                colour = INK, size = 4, fontface = "bold") +
      scale_fill_gradient(low = "#0a6b7a", high = CYAN, guide = "none") +
      scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
      labs(x = NULL, y = "Mean probability") + theme_tron() + tron_grid
  })

  output$p_scatter <- renderPlot(bg = PANEL, {
    s <- sessions(); if (!all(c("match_pct","sync_score") %in% names(s))) return(emptyplot("No data"))
    d <- s[!is.na(s$match_pct) & !is.na(s$sync_score), , drop = FALSE]
    if (!nrow(d)) return(emptyplot("No match/sync data"))
    p <- ggplot(d, aes(match_pct, sync_score)) +
      geom_point(colour = CYAN, fill = BG, shape = 21, size = 4, stroke = 1.3, alpha = 0.95)
    if (nrow(d) >= 3)
      p <- p + geom_smooth(method = "lm", se = FALSE, colour = ORANGE,
                           linewidth = 0.9, linetype = "dashed")
    p + labs(x = "Match %", y = "Sync score") + theme_tron() + tron_grid
  })
  output$p_person <- renderPlot(bg = PANEL, {
    s <- sessions(); if (!all(c("name","match_pct") %in% names(s))) return(emptyplot("No name data"))
    d <- s %>% group_by(name) %>% summarise(match = mean(match_pct, na.rm=TRUE), .groups="drop") %>%
      arrange(match) %>% mutate(name = factor(name, levels = name))
    ggplot(d, aes(match, name, fill = match)) +
      geom_col(width = 0.68) +
      geom_text(aes(label = lab_num(match, pct = TRUE)), hjust = -0.15,
                colour = INK, size = 4, fontface = "bold") +
      scale_fill_gradient(low = ORANGE, high = CYAN, guide = "none") +
      scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
      labs(x = "Avg Match %", y = NULL) + theme_tron() + tron_grid
  })
  output$p_corr <- renderPlot(bg = PANEL, {
    s <- sessions()
    cols <- intersect(c("duration_s","active_pct","kcal","upper_avg","lower_avg",
                        "overall_avg","match_pct","sync_score","zone_pct"), names(s))
    if (length(cols) < 3 || nrow(s) < 3) return(emptyplot("Need more sessions for correlation"))
    m <- cor(s[cols], use = "pairwise.complete.obs")
    d <- as.data.frame(as.table(m)); names(d) <- c("x","y","r")
    ggplot(d, aes(x, y, fill = r)) + geom_tile() +
      geom_text(aes(label = round(r,2)), colour = INK, size = 3) +
      scale_fill_gradient2(low = ALERT, mid = PANEL, high = CYAN, midpoint = 0, limits = c(-1,1)) +
      labs(x = NULL, y = NULL) + theme_tron() +
      theme(axis.text.x = element_text(angle = 40, hjust = 1))
  })

  dt_opts <- list(pageLength = 15, scrollX = TRUE)
  output$dt_sessions <- renderDT(datatable(sessions(), options = dt_opts, rownames = FALSE))
  output$dt_emotions <- renderDT(datatable(emotions(), options = dt_opts, rownames = FALSE))
  output$dt_timeline <- renderDT(datatable(timeline(), options = dt_opts, rownames = FALSE))
}

shinyApp(ui, server)

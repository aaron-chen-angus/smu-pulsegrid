# =============================================================================
# SMU//PULSE//GRID — R Shiny Analytics Dashboard
# Reads the live Google Sheet (3 tabs: Sessions, EmotionScans, IntensityTimeline)
# and provides KPIs, per-session drill-down, emotion before/after, movement
# intensity vs reference, and cohort analytics.
#
# ---------------------------------------------------------------------------
# SETUP (run once in R):
#   install.packages(c("shiny","shinydashboard","googlesheets4","dplyr",
#                      "tidyr","ggplot2","plotly","DT","lubridate","scales"))
#
# RUN LOCALLY:
#   setwd("path/to/dashboard"); shiny::runApp()
#
# DEPLOY (shinyapps.io):
#   install.packages("rsconnect")
#   rsconnect::setAccountInfo(name=..., token=..., secret=...)
#   rsconnect::deployApp("path/to/dashboard")
#
# DATA ACCESS: the sheet is shared "anyone with the link", so we read it without
#   login via googlesheets4::gs4_deauth(). If you later restrict the sheet, swap
#   to gs4_auth() and authorise once.
# =============================================================================

library(shiny)
library(shinydashboard)
library(googlesheets4)
library(dplyr)
library(tidyr)
library(ggplot2)
library(plotly)
library(DT)
library(lubridate)
library(scales)

# --- Config ------------------------------------------------------------------
SHEET_URL <- "https://docs.google.com/spreadsheets/d/1iYSFfDxljE1kT8cqAjHRvG2QVQ0374ZQRY-_e7cL_k8/edit"
REFRESH_SECONDS <- 60          # auto-refresh cadence
EMO_COLS <- c("neutral","happy","sad","angry","fearful","disgusted","surprised")

googlesheets4::gs4_deauth()    # public sheet: no OAuth needed

# --- Safe readers (return empty frames if a tab is missing/empty) ------------
read_tab <- function(tab) {
  out <- tryCatch(
    googlesheets4::read_sheet(SHEET_URL, sheet = tab, .name_repair = "minimal"),
    error = function(e) NULL
  )
  if (is.null(out)) data.frame() else as.data.frame(out)
}

num <- function(x) suppressWarnings(as.numeric(x))

load_all <- function() {
  sessions <- read_tab("Sessions")
  emotions <- read_tab("EmotionScans")
  timeline <- read_tab("IntensityTimeline")

  # Coerce numeric columns (read_sheet may infer types from sparse data).
  if (nrow(sessions)) {
    numcols <- c("match_distance","duration_s","active_pct","kcal","met_mean",
                 "upper_avg","upper_peak","upper_effort_pct","lower_avg","lower_peak",
                 "lower_effort_pct","overall_avg","match_pct","sync_score","zone_pct","weight_kg")
    for (c in intersect(numcols, names(sessions))) sessions[[c]] <- num(sessions[[c]])
    if ("sign_in_at" %in% names(sessions))
      sessions$sign_in_dt <- suppressWarnings(ymd_hms(sessions$sign_in_at, tz = "Asia/Singapore", quiet = TRUE))
  }
  if (nrow(emotions)) {
    for (c in intersect(c(EMO_COLS,"valence","arousal","neg_affect","frames"), names(emotions)))
      emotions[[c]] <- num(emotions[[c]])
  }
  if (nrow(timeline)) {
    for (c in intersect(c("t_s","user_upper","user_lower","user_overall",
                          "ref_upper","ref_lower","ref_overall","match_pct"), names(timeline)))
      timeline[[c]] <- num(timeline[[c]])
  }
  list(sessions = sessions, emotions = emotions, timeline = timeline)
}

# =============================================================================
# UI
# =============================================================================
ui <- dashboardPage(
  skin = "black",
  dashboardHeader(title = "SMU//PULSE//GRID"),
  dashboardSidebar(
    sidebarMenu(
      menuItem("Overview", tabName = "overview", icon = icon("gauge")),
      menuItem("Session drill-down", tabName = "session", icon = icon("person-running")),
      menuItem("Emotion & stress", tabName = "emotion", icon = icon("face-smile")),
      menuItem("Cohort analytics", tabName = "cohort", icon = icon("chart-line")),
      menuItem("Raw data", tabName = "raw", icon = icon("table"))
    ),
    actionButton("refresh", "Refresh now", icon = icon("rotate"),
                 style = "margin:10px;"),
    div(style = "color:#9fb3c8;font-size:12px;padding:0 12px;",
        textOutput("last_refresh"))
  ),
  dashboardBody(
    tags$head(tags$style(HTML("
      .content-wrapper{background:#0b1016;}
      .box{background:#0f1722;border-top-color:#00E5FF;}
      .small-box{border-radius:4px;}
      h2,h3,h4{color:#eaffff;}
    "))),
    tabItems(
      # ---- Overview ----
      tabItem("overview",
        fluidRow(
          valueBoxOutput("vb_sessions", width = 3),
          valueBoxOutput("vb_people", width = 3),
          valueBoxOutput("vb_match", width = 3),
          valueBoxOutput("vb_kcal", width = 3)
        ),
        fluidRow(
          box(title = "Sessions over time", width = 8, status = "primary",
              solidHeader = TRUE, plotlyOutput("p_sessions_time", height = 300)),
          box(title = "Completion", width = 4, status = "primary",
              solidHeader = TRUE, plotlyOutput("p_completion", height = 300))
        ),
        fluidRow(
          box(title = "Match % distribution", width = 6, status = "primary",
              solidHeader = TRUE, plotlyOutput("p_match_dist", height = 280)),
          box(title = "Upper vs Lower effort (vs instructor)", width = 6,
              status = "primary", solidHeader = TRUE,
              plotlyOutput("p_effort", height = 280))
        )
      ),
      # ---- Session drill-down ----
      tabItem("session",
        fluidRow(
          box(width = 12, status = "primary", solidHeader = TRUE,
              title = "Select a session",
              selectInput("sel_session", NULL, choices = NULL, width = "60%"))
        ),
        fluidRow(
          valueBoxOutput("sb_dur", width = 3),
          valueBoxOutput("sb_kcal", width = 3),
          valueBoxOutput("sb_match", width = 3),
          valueBoxOutput("sb_sync", width = 3)
        ),
        fluidRow(
          box(title = "Intensity timeline — you vs instructor", width = 12,
              status = "primary", solidHeader = TRUE,
              plotlyOutput("p_timeline", height = 360))
        ),
        fluidRow(
          box(title = "Emotion radar — Sign In vs Sign Out", width = 6,
              status = "primary", solidHeader = TRUE,
              plotlyOutput("p_radar", height = 360)),
          box(title = "Emotion change (Out − In)", width = 6,
              status = "primary", solidHeader = TRUE,
              plotlyOutput("p_delta", height = 360))
        )
      ),
      # ---- Emotion & stress ----
      tabItem("emotion",
        fluidRow(
          box(title = "Stress level: Sign In vs Sign Out", width = 6,
              status = "primary", solidHeader = TRUE,
              plotlyOutput("p_stress", height = 320)),
          box(title = "Valence change (In → Out) per session", width = 6,
              status = "primary", solidHeader = TRUE,
              plotlyOutput("p_valence", height = 320))
        ),
        fluidRow(
          box(title = "Mean emotion profile (all scans)", width = 12,
              status = "primary", solidHeader = TRUE,
              plotlyOutput("p_emo_profile", height = 320))
        )
      ),
      # ---- Cohort analytics ----
      tabItem("cohort",
        fluidRow(
          box(title = "Match % vs Sync score", width = 6, status = "primary",
              solidHeader = TRUE, plotlyOutput("p_scatter", height = 340)),
          box(title = "Average metrics per person", width = 6, status = "primary",
              solidHeader = TRUE, plotlyOutput("p_person", height = 340))
        ),
        fluidRow(
          box(title = "Correlation of session metrics", width = 12,
              status = "primary", solidHeader = TRUE,
              plotlyOutput("p_corr", height = 420))
        )
      ),
      # ---- Raw data ----
      tabItem("raw",
        tabsetPanel(
          tabPanel("Sessions", DTOutput("dt_sessions")),
          tabPanel("EmotionScans", DTOutput("dt_emotions")),
          tabPanel("IntensityTimeline", DTOutput("dt_timeline"))
        )
      )
    )
  )
)

# =============================================================================
# SERVER
# =============================================================================
server <- function(input, output, session) {

  # Reactive data store with timed + manual refresh.
  rv <- reactiveVal(load_all())
  observe({
    invalidateLater(REFRESH_SECONDS * 1000, session)
    rv(load_all())
  })
  observeEvent(input$refresh, { rv(load_all()) })

  output$last_refresh <- renderText(paste("Updated:", format(Sys.time(), "%H:%M:%S")))

  sessions <- reactive(rv()$sessions)
  emotions <- reactive(rv()$emotions)
  timeline <- reactive(rv()$timeline)

  # Populate the session selector.
  observe({
    s <- sessions()
    if (nrow(s) && "session_id" %in% names(s)) {
      labels <- if ("name" %in% names(s))
        paste0(s$name, "  (", s$session_id, ")") else s$session_id
      updateSelectInput(session, "sel_session",
                        choices = setNames(s$session_id, labels))
    }
  })

  # ---- Overview value boxes ----
  output$vb_sessions <- renderValueBox(
    valueBox(nrow(sessions()), "Sessions", icon = icon("list"), color = "aqua"))
  output$vb_people <- renderValueBox({
    n <- if ("name" %in% names(sessions())) length(unique(sessions()$name)) else 0
    valueBox(n, "Unique people", icon = icon("users"), color = "teal")
  })
  output$vb_match <- renderValueBox({
    v <- if ("match_pct" %in% names(sessions())) round(mean(sessions()$match_pct, na.rm = TRUE)) else NA
    valueBox(ifelse(is.na(v), "—", paste0(v, "%")), "Avg Match", icon = icon("bullseye"), color = "green")
  })
  output$vb_kcal <- renderValueBox({
    v <- if ("kcal" %in% names(sessions())) round(sum(sessions()$kcal, na.rm = TRUE), 1) else 0
    valueBox(v, "Total kcal", icon = icon("fire"), color = "orange")
  })

  # ---- Overview plots ----
  output$p_sessions_time <- renderPlotly({
    s <- sessions(); validate(need(nrow(s) > 0, "No sessions yet"))
    if (!"sign_in_dt" %in% names(s)) return(NULL)
    d <- s %>% mutate(day = as_date(sign_in_dt)) %>% count(day)
    plot_ly(d, x = ~day, y = ~n, type = "bar", marker = list(color = "#00E5FF")) %>%
      layout(paper_bgcolor = "#0f1722", plot_bgcolor = "#0f1722",
             font = list(color = "#cfe"), xaxis = list(title = ""), yaxis = list(title = "Sessions"))
  })

  output$p_completion <- renderPlotly({
    s <- sessions(); validate(need(nrow(s) > 0, "No sessions yet"))
    if (!"completed" %in% names(s)) return(NULL)
    d <- s %>% mutate(completed = tolower(as.character(completed)) %in% c("true","1","yes")) %>%
      count(completed) %>% mutate(lbl = ifelse(completed, "Completed", "Ended early"))
    plot_ly(d, labels = ~lbl, values = ~n, type = "pie", hole = 0.5,
            marker = list(colors = c("#FF8A00", "#3DFFB0"))) %>%
      layout(paper_bgcolor = "#0f1722", font = list(color = "#cfe"))
  })

  output$p_match_dist <- renderPlotly({
    s <- sessions(); validate(need("match_pct" %in% names(s) && any(!is.na(s$match_pct)), "No match data"))
    plot_ly(x = ~s$match_pct, type = "histogram", nbinsx = 20,
            marker = list(color = "#00E5FF")) %>%
      layout(paper_bgcolor = "#0f1722", plot_bgcolor = "#0f1722", font = list(color = "#cfe"),
             xaxis = list(title = "Match %"), yaxis = list(title = "Count"))
  })

  output$p_effort <- renderPlotly({
    s <- sessions(); validate(need(all(c("upper_effort_pct","lower_effort_pct") %in% names(s)), "No effort data"))
    d <- s %>% transmute(name = if ("name" %in% names(s)) name else session_id,
                         Upper = upper_effort_pct, Lower = lower_effort_pct) %>%
      pivot_longer(c(Upper, Lower), names_to = "group", values_to = "effort")
    plot_ly(d, x = ~name, y = ~effort, color = ~group, type = "bar",
            colors = c("#00E5FF", "#FF8A00")) %>%
      layout(barmode = "group", paper_bgcolor = "#0f1722", plot_bgcolor = "#0f1722",
             font = list(color = "#cfe"), xaxis = list(title = ""), yaxis = list(title = "Effort % vs instructor"))
  })

  # ---- Session drill-down ----
  cur_session <- reactive({
    s <- sessions(); req(input$sel_session)
    s[s$session_id == input$sel_session, , drop = FALSE]
  })

  output$sb_dur <- renderValueBox({
    r <- cur_session(); v <- if (nrow(r)) r$duration_s[1] else NA
    valueBox(ifelse(is.na(v), "—", sprintf("%d:%02d", v %/% 60, round(v %% 60))),
             "Duration", icon = icon("clock"), color = "aqua")
  })
  output$sb_kcal <- renderValueBox({
    r <- cur_session(); valueBox(ifelse(nrow(r), r$kcal[1], "—"), "kcal", icon = icon("fire"), color = "orange")
  })
  output$sb_match <- renderValueBox({
    r <- cur_session(); valueBox(ifelse(nrow(r), paste0(round(r$match_pct[1]), "%"), "—"),
                                 "Match", icon = icon("bullseye"), color = "green")
  })
  output$sb_sync <- renderValueBox({
    r <- cur_session(); valueBox(ifelse(nrow(r), round(r$sync_score[1]), "—"),
                                 "Sync", icon = icon("wave-square"), color = "teal")
  })

  output$p_timeline <- renderPlotly({
    t <- timeline(); req(input$sel_session)
    d <- t[t$session_id == input$sel_session, , drop = FALSE]
    validate(need(nrow(d) > 1, "No timeline for this session"))
    plot_ly(d, x = ~t_s) %>%
      add_lines(y = ~user_upper, name = "You · upper", line = list(color = "#00E5FF")) %>%
      add_lines(y = ~user_lower, name = "You · lower", line = list(color = "#FF8A00")) %>%
      add_lines(y = ~ref_overall, name = "Instructor · overall",
                line = list(color = "rgba(255,255,255,0.6)", dash = "dash")) %>%
      layout(paper_bgcolor = "#0f1722", plot_bgcolor = "#0f1722", font = list(color = "#cfe"),
             xaxis = list(title = "Time (s)"), yaxis = list(title = "Intensity (0–100)"))
  })

  radar_data <- reactive({
    e <- emotions(); req(input$sel_session)
    e[e$session_id == input$sel_session, , drop = FALSE]
  })

  output$p_radar <- renderPlotly({
    e <- radar_data(); validate(need(nrow(e) > 0, "No emotion scans"))
    mk <- function(row, nm, col) {
      vals <- as.numeric(row[EMO_COLS]); vals <- c(vals, vals[1])
      plot_ly(type = "scatterpolar", r = vals, theta = c(EMO_COLS, EMO_COLS[1]),
              fill = "toself", name = nm, line = list(color = col))
    }
    p <- plot_ly(type = "scatterpolar")
    ein <- e[e$phase == "in", , drop = FALSE]; eout <- e[e$phase == "out", , drop = FALSE]
    if (nrow(ein))  p <- p %>% add_trace(r = c(as.numeric(ein[1, EMO_COLS]), as.numeric(ein[1, EMO_COLS[1]])),
                                         theta = c(EMO_COLS, EMO_COLS[1]), fill = "toself",
                                         name = "Sign In", line = list(color = "#00E5FF"))
    if (nrow(eout)) p <- p %>% add_trace(r = c(as.numeric(eout[1, EMO_COLS]), as.numeric(eout[1, EMO_COLS[1]])),
                                         theta = c(EMO_COLS, EMO_COLS[1]), fill = "toself",
                                         name = "Sign Out", line = list(color = "#FF8A00"))
    p %>% layout(paper_bgcolor = "#0f1722", font = list(color = "#cfe"),
                 polar = list(bgcolor = "#0b1016", radialaxis = list(range = c(0, 1))))
  })

  output$p_delta <- renderPlotly({
    e <- radar_data(); validate(need(nrow(e) >= 2, "Need both scans"))
    ein <- e[e$phase == "in", EMO_COLS]; eout <- e[e$phase == "out", EMO_COLS]
    validate(need(nrow(ein) && nrow(eout), "Need both scans"))
    d <- data.frame(emotion = EMO_COLS,
                    delta = as.numeric(eout[1, ]) - as.numeric(ein[1, ]))
    plot_ly(d, x = ~emotion, y = ~delta, type = "bar",
            marker = list(color = ifelse(d$delta >= 0, "#FF8A00", "#00E5FF"))) %>%
      layout(paper_bgcolor = "#0f1722", plot_bgcolor = "#0f1722", font = list(color = "#cfe"),
             yaxis = list(title = "Out − In"))
  })

  # ---- Emotion & stress ----
  output$p_stress <- renderPlotly({
    e <- emotions(); validate(need("stress_level" %in% names(e) && nrow(e) > 0, "No stress data"))
    d <- e %>% count(phase, stress_level)
    plot_ly(d, x = ~phase, y = ~n, color = ~stress_level, type = "bar",
            colors = c("Normal" = "#3DFFB0", "Elevated" = "#FF8A00", "High" = "#FF3B5C")) %>%
      layout(barmode = "stack", paper_bgcolor = "#0f1722", plot_bgcolor = "#0f1722",
             font = list(color = "#cfe"), xaxis = list(title = ""), yaxis = list(title = "Scans"))
  })

  output$p_valence <- renderPlotly({
    e <- emotions(); validate(need(all(c("valence","phase","session_id") %in% names(e)), "No valence data"))
    w <- e %>% select(session_id, phase, valence) %>%
      pivot_wider(names_from = phase, values_from = valence) %>%
      filter(!is.na(`in`) & !is.na(out)) %>% mutate(change = out - `in`)
    validate(need(nrow(w) > 0, "Need in & out scans"))
    plot_ly(w, x = ~session_id, y = ~change, type = "bar",
            marker = list(color = ifelse(w$change >= 0, "#3DFFB0", "#FF3B5C"))) %>%
      layout(paper_bgcolor = "#0f1722", plot_bgcolor = "#0f1722", font = list(color = "#cfe"),
             xaxis = list(title = ""), yaxis = list(title = "Valence change"))
  })

  output$p_emo_profile <- renderPlotly({
    e <- emotions(); validate(need(nrow(e) > 0, "No emotion data"))
    m <- sapply(EMO_COLS, function(c) mean(e[[c]], na.rm = TRUE))
    plot_ly(x = names(m), y = as.numeric(m), type = "bar",
            marker = list(color = "#00E5FF")) %>%
      layout(paper_bgcolor = "#0f1722", plot_bgcolor = "#0f1722", font = list(color = "#cfe"),
             yaxis = list(title = "Mean probability"))
  })

  # ---- Cohort analytics ----
  output$p_scatter <- renderPlotly({
    s <- sessions(); validate(need(all(c("match_pct","sync_score") %in% names(s)), "No data"))
    plot_ly(s, x = ~match_pct, y = ~sync_score,
            text = if ("name" %in% names(s)) s$name else s$session_id,
            type = "scatter", mode = "markers",
            marker = list(color = "#00E5FF", size = 10)) %>%
      layout(paper_bgcolor = "#0f1722", plot_bgcolor = "#0f1722", font = list(color = "#cfe"),
             xaxis = list(title = "Match %"), yaxis = list(title = "Sync score"))
  })

  output$p_person <- renderPlotly({
    s <- sessions(); validate(need("name" %in% names(s), "No name column"))
    d <- s %>% group_by(name) %>%
      summarise(match = mean(match_pct, na.rm = TRUE),
                kcal = mean(kcal, na.rm = TRUE), .groups = "drop")
    plot_ly(d, x = ~name, y = ~match, type = "bar", name = "Avg Match %",
            marker = list(color = "#00E5FF")) %>%
      layout(paper_bgcolor = "#0f1722", plot_bgcolor = "#0f1722", font = list(color = "#cfe"),
             xaxis = list(title = ""), yaxis = list(title = "Avg Match %"))
  })

  output$p_corr <- renderPlotly({
    s <- sessions()
    cols <- intersect(c("duration_s","active_pct","kcal","upper_avg","lower_avg",
                        "overall_avg","match_pct","sync_score","zone_pct"), names(s))
    validate(need(length(cols) >= 3 && nrow(s) >= 3, "Need more sessions for correlation"))
    m <- cor(s[cols], use = "pairwise.complete.obs")
    plot_ly(x = colnames(m), y = rownames(m), z = m, type = "heatmap",
            colors = colorRamp(c("#FF3B5C", "#0f1722", "#00E5FF")), zmin = -1, zmax = 1) %>%
      layout(paper_bgcolor = "#0f1722", font = list(color = "#cfe"))
  })

  # ---- Raw tables ----
  dt_opts <- list(pageLength = 15, scrollX = TRUE)
  output$dt_sessions <- renderDT(datatable(sessions(), options = dt_opts, rownames = FALSE))
  output$dt_emotions <- renderDT(datatable(emotions(), options = dt_opts, rownames = FALSE))
  output$dt_timeline <- renderDT(datatable(timeline(), options = dt_opts, rownames = FALSE))
}

shinyApp(ui, server)

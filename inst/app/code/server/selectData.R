########################################
# EXAMPLE CSV DATA
########################################
csvnameVector <- c(
    "Simulated Rhythmic Transcripts" = system.file("extdata",
                                                   "Simphony_Example.csv",
                                    package = "DiscoRhythm", mustWork = TRUE)
    )

# Download File Names
downloadNameVector <- basename(csvnameVector)
names(downloadNameVector) <- names(csvnameVector)

########################################
# Data Collection
########################################

inputpath <- reactive({
    req(!is.null(input$inCSV$datapath) | input$selectInputType == "preload")
    if (input$selectInputType == "preload") {
      ret <- csvnameVector[input$preData]
    } else if (input$selectInputType == "csv") {
      ret <- input$inCSV$datapath
    }
    return(ret)
})

rawData <- reactive({
  req(!is.null(inputpath()))
  DiscoRhythm:::discoShinyHandler({
    data <- data.table::fread(inputpath(),
                              header = TRUE,
                              data.table = FALSE,
                              nrows = 1e5,
                              stringsAsFactors = FALSE
    )
    
    if (nrow(data) >= (1e5 - 1)) {
      warning("File too long, reading first 100,000 rows only")
    }
    
    data
  }, "Data Import",
  shinySession = session
  )
})

userMeta <- reactive({
  req(!is.null(input$inMetaCSV$datapath))
  DiscoRhythm:::discoShinyHandler({
        inputpath <- input$inMetaCSV$datapath
        data <- data.table::fread(inputpath,
                              header = TRUE,
                              data.table = FALSE,
                              nrows = 1e5,
                              stringsAsFactors = FALSE
        )
    
        if (nrow(data) >= (1e5 - 1)) {
          warning("File too long, reading first 100,000 rows only")
        }
        
        data
  }, "Data Import",
  shinySession = session
  )
})

selectDataSE <- reactive({
  req(!is.null(input$inCSV$datapath) | input$selectInputType == "preload")
  DiscoRhythm:::discoShinyHandler({
    if(!is.null(input$inMetaCSV$datapath)){
      se <- discoDFtoSE(rawData(),userMeta(),shinySession = session)
    }else{
      se <- discoDFtoSE(rawData(),shinySession = session)
    }
    final <- discoCheckInput(se)
    final
  }, "Data Import",
  shinySession = session
  )
})

Maindata <- reactive({
    req(selectDataSE())
    discoSEtoDF(selectDataSE())
})

# Low row number will cause skipping QC
hideQc <- reactive({
    req(Maindata())
    nrow(Maindata()) <= 10
})

# Metadata() is the main raw meta data object
# Created if Maindata() is created
Metadata <- reactive({
    req(selectDataSE())
    as.data.frame(SummarizedExperiment::colData(selectDataSE()))
})

########################################
# EXPLORATORY TABLES
########################################

output$rawSampleKey <- DT::renderDataTable({
    req(!is.null(Maindata()))
    nr <- nrow(Maindata())
    # Only show at most 50 rows
    Maindata()[1:min(nr, 50), ]
},
rownames = FALSE,
options = list(scrollX = TRUE, pageLength = 10, autoWidth = TRUE),
server = FALSE
)

output$rawMetadata <- DT::renderDataTable({
    req(!is.null(Metadata()))
    Metadata()
},
rownames = FALSE,
options = list(scrollX = TRUE, pageLength = 10, autoWidth = TRUE),
server = FALSE
)

output$sampleSummary <- output$compareSummary <- renderDT({
    req(!is.null(Metadata()))
    DT::datatable(discoDesignSummary(Metadata()),
        options = list(dom='t',
            ordering=FALSE, pageLength=500),
        selection='none') %>%
    formatStyle(" ",target="row",
        backgroundColor = styleEqual(c("Total"), colors$discoMain2))
}, rownames = TRUE, striped = TRUE,server=FALSE
)
########################################
# MISC
########################################
# Restart App
observeEvent(input$restartAppInSelectData, {
    showModal(
        modalDialog(
            size = "s",
            easyClose = TRUE,
            title = NULL,
            fade = FALSE, footer = NULL,
            p("Are you sure? All results will be lost."),
            actionButton("restartAppConfirmed", "Restart"),
            modalButton("Cancel")
            )
        )
})
observeEvent(input$restartAppConfirmed, {
    session$reload()
})

# Code to download example data
output$Example <- downloadHandler(
    filename = function() {
        downloadNameVector[input$preData]
    },
    content = function(file) {
        file.copy(csvnameVector[input$preData], file)
    }
    )


#############################
# Checks before proceeding
#############################

# Error messages when loading wrong data type/structure
observeEvent(input$inCSV, {
  # Wrong file format
    if (tolower(tools::file_ext(input$inCSV$name)) != "csv") {
        showModal(
            modalDialog(
                HTML(paste0(
                    "Expected .csv file, received .",
                    file_ext(input$inCSV$name),
                    "<br/> Please upload the correct data format
                    or use example datasets"
                    )),
                easyClose = TRUE, footer = NULL
                )
            )
    }
})

# Check if a dataset is loaded before allowing user to leave selectData section
observe({
    req(!(input$sidebar %in% c("selectData", "introPage")) &
        is.null(input$inCSV$name) & input$selectInputType == "csv")
    showModal(modalDialog(
        title = "Input Data Required",
        "Please upload a CSV or choose a demo CSV to continue",
        easyClose = TRUE
        ))

    updateTabItems(session, "sidebar", "selectData")
})

# Lock input after leaving
observe({
    req(input$sidebar != "selectData" &
        input$sidebar != "introPage")
    shinyjs::hide("inputSection")
    shinyjs::show("inputLocked")
})

# Preload summary table with values
observe({
    req(Metadata())
    req(Maindata())
    if (is.null(input$inCSV$name) & input$selectInputType == "csv") {
        shinyjs::hide("dataName")
        shinyjs::hide("summaryTable")
        summaryVal$nSamplesOri <- NA
        summaryVal$nRowsOri <- NA
    } else {
        req(Maindata())
        shinyjs::show("dataName")
        shinyjs::show("summaryTable")
        summaryVal$nSamplesOri <- nrow(Metadata())
        summaryVal$nRowsOri <- nrow(Maindata())
    }
    summaryVal$nSamples <- NA
    summaryVal$nRows <- NA
    summaryVal$corCutoff <- NA
    summaryVal$pcaCutoff <- NA
    summaryVal$ANOVAstate <- NA
    summaryVal$TRmerge <- NA
})

# Make sections inaccessible if no CSV loaded
observeEvent(input$selectInputType, {
    myTabs <- c("filtCorrelationInterCT", "pca", "metadata",
        "rowReplicateAnalysis", "overview", "regressionPage")
    if (input$selectInputType == "csv") {
        observe({
            if (is.null(input$inCSV$datapath) | is.null(selectDataSE())) {
                for (i in myTabs) {
                    addCssClass(selector = paste0("a[data-value='", i, "']"),
                        class = "inactiveLink")
                }
            } else {
                for (i in myTabs) {
                    removeCssClass(selector = paste0("a[data-value='", i, "']"),
                        class = "inactiveLink")
                }
            }
        })
    } else {
        for (i in myTabs) {
            removeCssClass(selector = paste0("a[data-value='", i, "']"),
                class = "inactiveLink")
        }
    }
})

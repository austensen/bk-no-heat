library(dplyr)
library(glue)
library(RPostgres)
library(DBI)
library(sf)
library(leaflet)
library(leaflet.mapboxgl) # remotes::install_github("rstudio/leaflet.mapboxgl")
library(leafpop)
library(htmlwidgets)
library(htmltools)
library(dotenv)


# Setup -------------------------------------------------------------------

# Edit ".env_sample" to set variables and save as ".env"
load_dot_env(".env")

# Free to sign up for API key here: https://account.mapbox.com/auth/signup/
options(mapbox.accessToken = Sys.getenv("MAPBOX_TOKEN"))

con <- dbConnect(
  drv = RPostgres::Postgres(),
  dbname = Sys.getenv("NYCDB_DB"),
  host = Sys.getenv("NYCDB_HOST"),
  user = Sys.getenv("NYCDB_USER"),
  password = Sys.getenv("NYCDB_PW"),
  port = Sys.getenv("NYCDB_PORT")
)


# Prep data ---------------------------------------------------------------

bbl_data <- dbGetQuery(con, "
WITH no_heat_problems AS (
  SELECT DISTINCT complaintid -- only one for each complaint
  FROM hpd_complaint_problems
  WHERE code ~ 'NO HEAT' -- description of the problem contains the phrase 'NO HEAT'
    AND statusdate between '2021-10-01' and '2022-05-31' -- 'heat season'
    AND (unittype = 'BUILDING-WIDE' OR minorcategory = 'ENTIRE BUILDING') -- these do not always agree
    
), no_heat_bbls AS (
	SELECT 
	  c.bbl, 
	  count(*) AS no_heat_complaints
	FROM hpd_complaints AS c
	INNER JOIN no_heat_problems AS p
	  USING(complaintid)
	WHERE bbl ~ '^3'
	GROUP BY c.bbl
	ORDER BY no_heat_complaints desc
)
SELECT n.*, p.address, p.unitsres as units, p.latitude,  p.longitude
FROM no_heat_bbls as n
LEFT JOIN pluto_20v8 as p 
	USING(bbl)
WHERE latitude is not null;
")

map_data <- bbl_data %>% 
  st_as_sf(coords = c("longitude", "latitude")) %>% 
  transmute(
    `Address` = address,
    `Complaints` = no_heat_complaints,
    `Units` = units,
    `Links` = glue("
      <a href='https://whoownswhat.justfix.nyc/bbl/{bbl}'>WhoOwnsWaht</a></br>
      <a href='https://portal.displacementalert.org/property/{bbl}'>DAP Portal</a>"),
  )


# Make Map ----------------------------------------------------------------

map_title <- tags$div(
  HTML(glue("<h3>Building-Wide No Heat Complaints</h3><span>2021/22 Heat Season (last updated: {Sys.Date()})</span>"))
)  

popup <- popupTable(
  map_data, 
  c("Address", 
    "Complaints", 
    "Units",
    "Links"), 
  row.numbers = FALSE, 
  feature.id = FALSE
)

no_heat_map <- map_data %>% 
  leaflet() %>% 
  addMapboxGL(style = "mapbox://styles/mapbox/light-v9") %>%
  addControl(map_title, position = "topright") %>% 
  addCircleMarkers(
    fillOpacity = 0.7,
    color = "steelblue",
    weight = 0,
    radius = 3,
    opacity = 0.8,
    popup = popup
  )

saveWidget(no_heat_map, file="docs/map.html")

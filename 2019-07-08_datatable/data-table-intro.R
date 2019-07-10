
# My default packages
#######################
library(stringr)
library(purrr)
library(magrittr)
library(data.table)
library(lubridate)
library(ggplot2)
library(openxlsx)
library(zoo)
library(xts)
#######################
library(microbenchmark)


# read in the flights data
# https://www.kaggle.com/usdot/flight-delays
# data.table::fread() reads text data fast
flights <- fread("data/flights.csv")

# What is a data.table ?
class(flights)
# It is an extension of the data.frame class


# Subsetting a data.table has a simple syntax
# DT[i, j, by]
# 
# i filters rows (analagous to a WHERE clause in SQL)
# j is how you select/compute on columns 
# by is where you can group computations 


# i ============================================================================
# first index is ALWAYS rows, regardless of commas
identical(flights[2], flights[2,])

# compare to data.frame
as.data.frame(flights)[2]  %>% dim
as.data.frame(flights)[2,] %>% dim

# use i to select rows
flights[1:2] # first and second row
flights[2:1] # second and first row

# it can take logical expressions
flights[MONTH == 1]
flights[MONTH == 1 & DISTANCE > 1000]

# and there's also some convenience functions baked in
identical(flights[-1:-100000], flights[!1:100000])

# order() is optimized within a data.table
# makes sorting a cinch
# sort by one column and then another 
# (minus means descending)
flights[order(TAIL_NUMBER,-ARRIVAL_DELAY)]
# sort by a function on our data
flights[order(substr(ORIGIN_AIRPORT,1,1))]

# you can chain queries together
flights[!is.na(ARRIVAL_DELAY)][order(TAIL_NUMBER,-ARRIVAL_DELAY)]

# sometimes you'll see chains piped together like this 
flights %>%
  .[!is.na(ARRIVAL_DELAY)] %>%
  .[order(TAIL_NUMBER,-ARRIVAL_DELAY)]
  

# j ============================================================================
# computations on columns

# select columns by name in the second index parameter
flights[ , DESTINATION_AIRPORT]           # as a vector
flights[ , list(DESTINATION_AIRPORT)]     # as a data.table
# use list to select multiple columns
flights[ , list(DESTINATION_AIRPORT, ORIGIN_AIRPORT)]


# data.table has lots of convenience functions  
# .() is the same as list()
flights[ , .(DESTINATION_AIRPORT, ORIGIN_AIRPORT)] 


# you can compute on columns as well
flights[ , unique(ORIGIN_AIRPORT)]
flights[ , sum(AIR_TIME, na.rm = TRUE) / (1e6 * 60)]
flights[ , summary(as.factor(CANCELLATION_REASON))]
flights[ , .(AIR_TIME, AIR_TIME/60)] # return multiple columns
# and since we're pulling things out using a list, you can name the items
flights[ , .(AIR_TIME, AIR_TIME_HOURS = AIR_TIME/60)] 
# anytime the j expression returns a list, the whole expression will return
# a data.table



# combining i and j ============================================================

# now we're cooking

# How many flights were delayed touching down?
flights[ARRIVAL_DELAY>0, .N] 
      # .N is a convenience symbol to get the number of rows in a data.table

# What are some summary statistics of the delayed flights (in hours)?
flights[ARRIVAL_DELAY>0, summary(ARRIVAL_DELAY/60)]


# How many flights were on each day of the week?
flights[ARRIVAL_DELAY>0, plot(table(DAY_OF_WEEK))] 
      # again, we don't have to return a data.table
      # an expression that returns a list in j would,
      # but here we want to plot, and data.table 
      # evaluates the expression correctly



# by ===========================================================================
# grouping

# How many outgoing flights did each aiport have?
flights[ , .N, by = ORIGIN_AIRPORT]
# Let's order it to see the biggest airports
flights[ , .N, by = ORIGIN_AIRPORT][order(-N)]


# Which airports had the most cancelled flights?
flights[CANCELLED == 1, .N, by = ORIGIN_AIRPORT][order(-N)]

# Same thing, but using pipes
# Here we use extract, magrittr's alias for [ rather than the .[] notation above
flights %>%
  extract(CANCELLED == 1, .N, by = ORIGIN_AIRPORT) %>%
  extract(order(-N))


# What's the min and max departure delay for each airport, sorted by biggest 
# difference between the two?
flights[ , .(MinDelay = min(DEPARTURE_DELAY, na.rm = TRUE), 
             MaxDelay = max(DEPARTURE_DELAY, na.rm = TRUE)), 
         by = ORIGIN_AIRPORT][order(MinDelay-MaxDelay)]
      # Again, order can take functions of the data
      # Very versatile!


# .SD ==========================================================================


# .SD is a special name for the subset of the data.table for each group
mtcarsDT <- as.data.table(mtcars, keep.rownames = 'Model')
mtcarsDT[ ,unique(cyl)] # we have three groups by cylinder count
mtcarsDT[ , print(.SD), by = cyl] # so we have three data.tables that get printed
# it is itself a data.table
# meaning it can be operated on!
# https://www.youtube.com/watch?v=L6aT_oEhIKo

# first two rows of flights from each day
flights[ , .SD[1:2], by = .(YEAR,MONTH,DAY)] 
# 100 random obs from every day
flights[ , .SD[sample(1:.N, 100)], by = .(YEAR, MONTH,DAY)] 


# Pct of flights cancelled by airport
flights %>%
  extract( , .(PctCancelled = .SD[CANCELLED == 1,.N] / .N), by = ORIGIN_AIRPORT) %>%
  extract(order(-PctCancelled))
    # This one can be tricky. Since .SD is a data.table the first .N, being
    # inside .SD[], refers to the number of rows of the subgroup
    # But we've filtered it to be only the cancelled flights, so the .SD
    # expression returns the number of flights cancelled
    # we then divide it by the total number of flights in the group (the
    # second .N) to find the percent of flights cancelled

# the last example is meant to be instructive and not recommended practice
# since we could always compute the figure quicker and more simply like this:
flights[ , .(PctCancelled = mean(CANCELLED)), by = ORIGIN_AIRPORT][order(-PctCancelled)]

# but it's important because you can do lot of little tricks using .SD
# like filtering out groups

# Remove all airports from the dataset that don't have 10k flights
flights[ , .SD[.N >= 10000], by = ORIGIN_AIRPORT]
    # Here we're saying to group by the airport of origin
    # So .SD in each case is the complete set of flights for an airport
    # We then filter that subset. We put in a single TRUE or FALSE, is the 
    # number of rows greater than 10000? If it is, it returns TRUE and is
    # recycled so that every row in the subset is returned. If not, then
    # the FALSE is returned, recycled for all rows, and no rows are returned
    # Data.table will build up the final dataset based on these little data.tables
    # Appending zero rows to a data.table means nothing, and the airports
    # that don't have enough rows are dropped from the final output

# Which airports don't have 10000 flights?
flights[ , .SD[.N < 10000], by = ORIGIN_AIRPORT][ , unique(ORIGIN_AIRPORT)]



# Assignment ===================================================================

# there is an assignment operator that *modifies in place* (by reference)
# jargon translation: it will alter the specific object you use it on


# this is useful for converting column types

# Create a date column that's in date format
flights[ , Date := ymd(YEAR*10000+MONTH*100+DAY)]
# Reformat the dataset into boolean format
flights[ , CANCELLED := ifelse(CANCELLED == 1, TRUE, FALSE)]


# and useful or creating new columns
flights[ , AvgSpeed := DISTANCE / (AIR_TIME/60)]


# can be done to selectively update your data.table
flights[ CANCELLATION_REASON2 == 'A', CANCELLATION_REASON := 'Airline' ]
flights[ CANCELLATION_REASON2 == 'B', CANCELLATION_REASON := 'Weather'] 
flights[ CANCELLATION_REASON2 == 'C', CANCELLATION_REASON := 'National Air System'] 
flights[ CANCELLATION_REASON2 == 'D', CANCELLATION_REASON := 'Security'] 
flights[ CANCELLATION_REASON2 == '', CANCELLATION_REASON := NA] 

flights[!is.na(CANCELLATION_REASON2), .N, by = CANCELLATION_REASON2] %>%
  ggplot(aes(x = CANCELLATION_REASON2, y = N)) +
  geom_histogram(stat = 'identity')


# I like making functions for this
cancelReasonUpdate <- function(inStr){
  switch(inStr,
         "A" = "Airline",
         "B" = "Weather",
         "C" = "National Air System",
         "D" = "Security",
               NA)
}

flights[ , CANCELLATION_REASON2 := map_chr(CANCELLATION_REASON,cancelReasonUpdate)]

# Can also be used to delete columns
flights[ , CANCELLATION_REASON2 := NULL]


# can also be used when grouping
flights[ , MaxAvgSpeed := max(AvgSpeed, na.rm = TRUE), by = .(ORIGIN_AIRPORT, DESTINATION_AIRPORT)]
    # note that the group level statistic is now added to each observation

# joins ========================================================================

# read in the list of airports
airports <- fread("data/airports.csv")


# inner join 
merge(x = flights,
      y = airports,
      by.x = 'ORIGIN_AIRPORT',
      by.y = 'local_code')

# left outer join 
flights[airports, on = c(ORIGIN_AIRPORT = 'IATA_CODE')]
flights[airports, on = "ORIGIN_AIRPORT == IATA_CODE"]

# inner join 
flights[airports, on = c(ORIGIN_AIRPORT = 'IATA_CODE'), nomatch = 0]


# not join (aka anti-join)
airports[!flights, on = "IATA_CODE == ORIGIN_AIRPORT"]


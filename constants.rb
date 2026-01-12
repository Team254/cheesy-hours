# Days that students are required to be in the lab. If as student signs in on
# one of these days, all other students will be marked missing on the calendar
# if they are not present. Conversely, if a student signs in on a day not in
# this list, an optional build will be created for that day.
REQUIRED_BUILD_DAYS = ["Monday", "Wednesday", "Friday", "Saturday"]

# The time zone that end users will be in (all times will be presented in
# this time zone). Some queries make assumptions about time zone and may
# need to be edited if used outside California.
USER_TIME_ZONE = "America/Los_Angeles"
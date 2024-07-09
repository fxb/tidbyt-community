"""
Applet: HVV Departures
Summary: HVV Departures
Description: Display real-time departure times for trains, buses and ferries in Hamburg (HVV).
Author: fxb (Felix Bruns)
"""

load("cache.star", "cache")
load("encoding/base64.star", "base64")
load("encoding/json.star", "json")
load("hmac.star", "hmac")
load("http.star", "http")
load("math.star", "math")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

# The API endpoints used to retrieve locations and departures.
#
# This applet uses APIs provided by https://transport.rest/, which provide
# real-time data, without any API keys, reasonable rate-limits and for free.
#
# Currently this applet only supports departure times for Hamburg (HVV),
# but can theoretically be re-used for Berlin & Brandenburg (VBB, BVG) or
# even "Deutsche Bahn" long-distance trains.
#
GTI_API_URL = "https://gti.geofox.de/gti/public/{method}"
GTI_API_VERSION = 54
GTI_API_METHOD_INIT = "init"
GTI_API_METHOD_CHECK_NAME = "checkName"
GTI_API_METHOD_DEPARTURE_LIST = "departureList"
GTI_API_DATE_FORMAT = "02.01.2006"
GTI_API_TIME_FORMAT = "15:04"

# The default station ID to use, if none is set by the user.
# This currently defaults to "Hamburg Hbf" (main station).
GTI_API_DEFAULT_STATION_ID = "Master:9910950"

# Cache API responses for a short time, as we want things to be as recent as possible.
GTI_API_CACHE_TTL_SECONDS = 30

# A mapping of applet configuration options to GTI API service types.
OPTIONS_TO_GTI_API_SERVICE_TYPES = {
    "include_subway": ["UBAHN"],
    "include_suburban": ["SBAHN"],
    "include_bus": [
        "BUS",
        "STADTBUS",
        "METROBUS",
        "NACHTBUS",
        "SCHNELLBUS",
        "XPRESSBUS"
    ],
    "include_akn": ["AKN"],
    "include_regional_train": ["RBAHN"],
    "include_long_distance_train": ["FERNBAHN"],
    "include_ferry": ["FAEHRE"],
}

OPTION_SERVICE_ALL = "{}"

# The RFC3339 date and time format string used by Go / Starlark.
RFC3339_FORMAT = "2006-01-02T15:04:05Z07:00"

# Background images for known lines, as well as the HVV logo.
IMAGE_LOGO = base64.decode("iVBORw0KGgoAAAANSUhEUgAAACAAAAAKCAYAAADVTVykAAABhUlEQVR4AbzTA4ycQRTA8VfbthvUtm3bilXHNYLathnVto2zbWsx97/LYrIKDi/5LR8G+USUPMFslBFL5DQdUh07sU+KPJT8RxB2oy9KMbghfBBVHAtoglVIRDJa6wtAfSzEXmxBJ1TGRCxGbdGC720xD8PR2ZLT1yGnMqZjkTBwPd4jFfdRW1tAJE4iA8riFwbhLhQW5TQZXFJrfgAGbMVEKDxFRS2nD5IRKgyMxRG0FEtoCzBjHzpbnIHCTQxBDP6jo1aXiQA0y248sATvX5CFMfk5TYaU4/NlJGKFMLimOIS2AAO7q+hwvAqfc5oOrs37NihsRTlshMIOrWYB4nHNMnw2YnCD3mXFIRwXECNaUFDDMuAbn6vx3hxp+ItZCMZntHe478uIwly8RgpGirtw9xQYmgypri/AknsRRoRBYR5KOvQbjkyEwozHnEb5wlpAD3hDIdDgcKyWnEp4AYV0TBNPQUIV7MBOhwXkNTqGTSygnJY/D0cw2EPPgZba3OUj5wgA0xFcXLHDZ2kAAAAASUVORK5CYII=")
IMAGE_METRO_BUS = base64.decode("iVBORw0KGgoAAAANSUhEUgAAABAAAAAJCAYAAAA7KqwyAAAAd0lEQVR42qWMsQ2AMAwET2IPkp4paGlYgxnYkykgKLSIKPgLJDogvPSS/f4zlxZ8H/CHOT/4UJe7Zlxrh6jCS0cxSIG6sWDT4aM3sdgwKSj0hIY/JuDmUlgsK66zJRU8SGKRVvxgwf4B3sVwKUO14Ma3D9QVA3AC2DYHRN4mmqoAAAAASUVORK5CYII=")
IMAGE_XPRESS_BUS = base64.decode("iVBORw0KGgoAAAANSUhEUgAAABAAAAAJCAYAAAA7KqwyAAAAaklEQVR4AZ3QsQ2AIBCFYRL3cAEWsLWlYQ1nYBEnYwobbAlG3yteLXeX/OX3igu69dwyGuj9aaAsJ7yjNoFVoxGO6DZgRRM5UB1Y1eDFigOXF9NyIKHHgWmSHnmgbsCdhlYDCyqGgUJD+wGOhfahrZQnuQAAAABJRU5ErkJggg==")
IMAGE_NIGHT_BUS = base64.decode("iVBORw0KGgoAAAANSUhEUgAAABAAAAAJCAQAAACRI2S5AAAAXElEQVR42n3PoQ2AQAAEwU2+k7VUgcXQBjXQJ1VgwBLIIXDwT07OmgPE0dO8djoCIPZuH45xswfs3Ksc426HS5NjXPjlGFx/gxUHryZfDoiTR5UPp+dmca4GswVu/YOM52Hx5vcAAAAASUVORK5CYII=")
IMAGE_S1 = base64.decode("iVBORw0KGgoAAAANSUhEUgAAAA4AAAAJCAYAAAACTR1pAAAAa0lEQVR4AWMAAfEpWuZSU7WeSk7Tei01Tfs/NgyVeyI5TcMYrklyqtZHkCQxGKRWcrK6CQPIJpAAifgJA5D4QKpGoGVvGEAMcjDZNpLvR1DwkhSq07Q+iU7SMgRHCSh4QaaAnIDPeSA1ME0Aow/ZmIBU42QAAAAASUVORK5CYII=")
IMAGE_S2 = base64.decode("iVBORw0KGgoAAAANSUhEUgAAAA4AAAAJCAYAAAACTR1pAAAAbUlEQVR42p1QQQqAQAj0CYF+JFpa99ct65PqVIfqA9Uc6hTRKgyIOo4OIQbWWDhNRXQ2Sccb0Cuso0nsHpKxbmj+AWaz9IGghEINoEzGujqICyHxwK3o/xH21rh6Ce25CS0hYC+24ISv8zBzk04OP+ukjEgl2AAAAABJRU5ErkJggg==")
IMAGE_S3 = base64.decode("iVBORw0KGgoAAAANSUhEUgAAAA4AAAAJCAYAAAACTR1pAAAAbElEQVR4AWMAgWCFbPMQhdynIYp5r4H4PzYMllPIexIgl2eM0KSY+xEiSRiD1AbL5pgwQG36TwoG2cwANOEDqRqDFXLfMIAY5GCybSTfj6DgJSVUgxXzPgXL5xqCowQUvCBTQE7A5zyQGpgmAHpv3XJOylpCAAAAAElFTkSuQmCC")
IMAGE_S5 = base64.decode("iVBORw0KGgoAAAANSUhEUgAAAA4AAAAJBAMAAADwYwBaAAAAGFBMVEUAk8EAk8EAk8EAk8EAk8EAk8EAk8EAk8EVErdJAAAACHRSTlMBgOf/fYXodmMUWLwAAAAnSURBVAjXY2BUNjY2NnJgCDYGAVOGZDBtxmAMARg0TB6mngWsvwAAzTQM/yA8BKUAAAAASUVORK5CYII=")
IMAGE_AKN = base64.decode("iVBORw0KGgoAAAANSUhEUgAAAA4AAAAJCAYAAAACTR1pAAAAVElEQVR4AWMAgX8NkuZA/BSIPwDxfxz4NRA/AWJjZE0fIZKEMVStCQPUpv8k4icMMOeRiN8wgBjkYLJtpMiPxiSG6icgNoRFiQk0jt7gcx5IDUwTAGj6M5mAtFVfAAAAAElFTkSuQmCC")
IMAGE_FERRY = base64.decode("iVBORw0KGgoAAAANSUhEUgAAAA4AAAAJBAMAAADwYwBaAAAAJ1BMVEUAk8EAk8EAk8EAk8EAk8EAk8EAk8EAk8EAk8EAAAAAk8EAk8EAk8EaPqQDAAAADXRSTlPo/8CYaHBASBgA8MiggFTfDQAAADNJREFUCNdjYBQEAQEGRTAtxGAIpoUZHMG0KEMimBZnaATTEgyzwPRKhtlgeifDZDB9EgDq8gjgrMqy9QAAAABJRU5ErkJggg==")

# Configuration for backgrounds and colors for all known lines.
LINE_CONFIG = {
    # Subways (U-Bahn)
    "u1": {"background-color": "#0072bc", "color": "#ffffff"},
    "u2": {"background-color": "#ed1c24", "color": "#ffffff"},
    "u3": {"background-color": "#ffde00", "color": "#2f2f2f"},
    "u4": {"background-color": "#00aaad", "color": "#ffffff"},

    # Suburban trains (S-Bahn)
    "s1": {"image": IMAGE_S1, "color": "#ffffff"},
    "s2": {"image": IMAGE_S2, "color": "#ffffff"},
    "s3": {"image": IMAGE_S3, "color": "#ffffff"},
    "s5": {"image": IMAGE_S5, "color": "#ffffff"},

    # AKN commuter trains
    "a1": {"image": IMAGE_AKN, "color": "#ffffff"},
    "a2": {"image": IMAGE_AKN, "color": "#ffffff"},
    "a3": {"image": IMAGE_AKN, "color": "#ffffff"},

    # Buses (MetroBus, XpressBus, NachtBus)
    "metro_bus": {"image": IMAGE_METRO_BUS, "color": "#ffffff"},
    "xpress_bus": {"image": IMAGE_XPRESS_BUS, "color": "#ffffff"},
    "night_bus": {"image": IMAGE_NIGHT_BUS, "color": "#ffffff"},

    # Regional trains (Regional Bahn, Regional Express)
    "rb": {"background-color": "#2f2f2f", "color": "#ffffff"},
    "re": {"background-color": "#2f2f2f", "color": "#ffffff"},

    # Long distance trains (Inter City Express)
    "ice": {"color": "#ffffff"},

    # Ferries
    "ferry": {"image": IMAGE_FERRY, "color": "#ffffff"},
}

# These are used as fallbacks in case there is no specific config above.
# Basically this will result in only rendering the plain line name, without
# any background image or color.
DEFAULT_SUBWAY_CONFIG = {"color": "#ffffff"}
DEFAULT_SUBURBAN_CONFIG = {"color": "#ffffff"}
DEFAULT_BUS_CONFIG = LINE_CONFIG["metro_bus"]
DEFAULT_REGIONAL_TRAIN_CONFIG = LINE_CONFIG["rb"]
DEFAULT_LONG_DISTANCE_TRAIN_CONFIG = LINE_CONFIG["ice"]
DEFAULT_FERRY_CONFIG = LINE_CONFIG["ferry"]

# Other colors used throughout the applet.
COLOR_BACKGROUND = "#000000"
COLOR_SEPARATOR = "#1f1f1f"
COLOR_MESSAGE_INFO = "#ffffff"
COLOR_MESSAGE_ERROR = "#ff9900"
COLOR_DEPARTURE_TIME = "#ff9900"
COLOR_DEPARTURE_TIME_DELAYED = "#ff0000"
COLOR_DEPARTURE_TIME_ON_TIME = "#00ff00"

def render_subway_icon(type, name):
    """Render a rectangular subway (U-Bahn) icon.

    Args:
        type: The type of the subway line.
        name: The name of the subway line.

    Returns:
        A definition of what to render.
    """
    data = LINE_CONFIG.get(name.lower(), DEFAULT_SUBWAY_CONFIG)
    background_color = data.get("background-color", "#000000")
    color = data.get("color", "#ffffff")
    return render.Box(width = 18, height = 15, padding = 2, child = render.Stack(children = [
        render.Box(width = 14, height = 9, color = background_color) if background_color != None else None,
        render.Box(width = 16, height = 9, child = render.Text(name, offset = -1, font = "tom-thumb", color = color)),
    ]))

def render_suburban_icon(type, name):
    """Render a pill shaped suburban train (S-Bahn) icon.

    Args:
        type: The type of the suburban train line.
        name: The name of the suburban train line.

    Returns:
        A definition of what to render.
    """
    data = LINE_CONFIG.get(name.lower(), DEFAULT_SUBURBAN_CONFIG)
    image = data.get("image", None)
    color = data.get("color", "#ffffff")
    return render.Box(width = 18, height = 15, padding = 2, child = render.Stack(children = [
        render.Image(width = 14, height = 9, src = image) if image != None else None,
        render.Box(width = 16, height = 9, child = render.Text(name, offset = -1, font = "tom-thumb", color = color)),
    ]))

def render_bus_icon(type, name):
    """Render a diamond like bus (MetroBus, XpressBus or NachtBus) icon.

    Args:
        type: The type of the bus line.
        name: The name of the bus line.

    Returns:
        A definition of what to render.
    """
    is_xpress_bus = type == "XpressBus"
    is_night_bus = type == "Nachtbus"
    data = LINE_CONFIG.get("xpress_bus" if is_xpress_bus else "night_bus" if is_night_bus else "metro_bus", DEFAULT_BUS_CONFIG)
    image = data.get("image", None)
    color = data.get("color", "#ffffff")
    expand = len(name) > 3
    return render.Box(width = 18, height = 15, padding = 0 if expand else 1, child = render.Stack(children = [
        render.Image(width = 18 if expand else 16, height = 9, src = image) if image != None else None,
        render.Box(width = 20 if expand else 18, height = 9, child = render.Text(name, offset = -1, font = "tom-thumb", color = color)),
    ]))

def render_regional_train_icon(type, name):
    """Render a rectangular regional (express) train (Regional-Bahn, Regional-Express) icon.

    Args:
        type: The type of the regional train line.
        name: The name of the regional train line.

    Returns:
        A definition of what to render.
    """
    data = LINE_CONFIG.get(type, DEFAULT_REGIONAL_TRAIN_CONFIG)
    background_color = data.get("background-color", "#000000")
    color = data.get("color", "#ffffff")
    return render.Box(width = 18, height = 15, padding = 1, child = render.Stack(children = [
        render.Box(width = 15, height = 13, color = background_color),
        render.Column(children = [
            render.Box(height = 6, child = render.Text(name[0:2], offset = -1, font = "tom-thumb", color = color)),
            render.Box(height = 6, child = render.Text(name[2:], offset = -1, font = "tom-thumb", color = color)),
        ]),
    ]))

def render_long_distance_train_icon(type, name):
    """Render a rectangular regional (express) train (Regional-Bahn, Regional-Express) icon.

    Args:
        type: The type of the regional train line.
        name: The name of the regional train line.

    Returns:
        A definition of what to render.
    """
    data = LINE_CONFIG.get(type, DEFAULT_LONG_DISTANCE_TRAIN_CONFIG)
    color = data.get("color", "#ffffff")
    return render.Box(width = 18, height = 15, padding = 1, child = render.Column(children = [
        render.Box(height = 6, child = render.Text(name, offset = -1, font = "tom-thumb", color = color)),
    ]))

def render_ferry_icon(type, name):
    """Render a trapeze shaped ferry (Fähre) icon.

    Args:
        type: The type of the ferry line.
        name: The name of the ferry line.

    Returns:
        A definition of what to render.
    """
    data = LINE_CONFIG.get(name.lower(), DEFAULT_FERRY_CONFIG)
    image = data.get("image", None)
    color = data.get("color", "#ffffff")
    return render.Box(width = 18, height = 15, padding = 2, child = render.Stack(children = [
        render.Image(width = 14, height = 9, src = image) if image != None else None,
        render.Box(width = 16, height = 9, child = render.Text(name, offset = -1, font = "tom-thumb", color = color)),
    ]))

def render_line_icon(line):
    """Render an icon for a given line.

    Args:
        line: A "line" dictionary, retrieved from the API.

    Returns:
        A definition of what to render.
    """
    type = line["type"]["shortInfo"]
    name = line["name"]

    if type == "U":
        return render_subway_icon(type, name)
    elif type == "S" or \
         type == "A":
        return render_suburban_icon(type, name)
    elif type == "Bus" or \
         type == "XpressBus" or \
         type == "Nachtbus":
        return render_bus_icon(type, name)
    elif type == "RB" or \
         type == "RE":
        return render_regional_train_icon(type, name)
    elif type == "ICE":
        return render_long_distance_train_icon(type, name)
    elif type == "Schiff":
        return render_ferry_icon(type, name)

    # Fallback to just rendering nothing.
    return render.Box()

def split_duration(duration):
    hours = math.floor(duration.hours)
    minutes = math.floor(duration.minutes) - hours * 60
    return (hours, minutes)

def render_relative_departure_time(time_base, time_actual):
    """Render a relative departure time.

    Args:
        time_base: The time to use as a reference.
        time_actual: The actual departure time.

    Returns:
        A definition of what to render.
    """
    (diff_hours, diff_minutes) = split_duration(time_actual - time_base)

    return render.Text(
        content = "now"
            if diff_hours <= 0 and diff_minutes <= 0
            else "{}h {}m".format(diff_hours, diff_minutes)
            if diff_hours > 0
            else "{} min".format(diff_minutes),
        height = 7,
        font = "tb-8",
        color = COLOR_DEPARTURE_TIME,
    )

def render_absolute_departure_time(format, time_base, time_planned, time_actual):
    """Render an absolute departure time, including a delay indicator.

    Args:
        format: The time layout string to use.
        time_base: The time to use as a reference.
        time_planned: The planned departure time.
        time_actual: The actual departure time.

    Returns:
        A definition of what to render.
    """
    (delay_hours, delay_minutes) = split_duration(time_actual - time_planned)

    return render.Row(children = [
        render.Text(
            content = time_planned.format(format),
            height = 7,
            font = "tb-8",
            color = COLOR_DEPARTURE_TIME,
        ),
        render.Text(
            content = "+0"
                if delay_hours <= 0 and delay_minutes <= 0
                else "+{}h{}m".format(delay_hours, delay_minutes)
                if delay_hours > 0
                else "+{}".format(delay_minutes),
            height = 7,
            font = "tom-thumb",
            color = COLOR_DEPARTURE_TIME_DELAYED
                if delay_hours > 0 or delay_minutes > 0
                else COLOR_DEPARTURE_TIME_ON_TIME,
        ),
    ])

def render_departure_time(time_format, time_base, time_planned, time_actual):
    """Render a relative or an absolute departure time.

    Args:
        time_format: The time layout string to use or "relative".
        time_base: The time to use as a reference.
        time_planned: The planned departure time.
        time_actual: The actual departure time.

    Returns:
        A definition of what to render.
    """
    if time_format == "relative":
        return render_relative_departure_time(time_base, time_actual)
    else:
        return render_absolute_departure_time(time_format, time_base, time_planned, time_actual)

def render_departure(departure, time_base, time_offset, time_format):
    """Render which line, including icon, departs at what time.

    Args:
        departure: A "departure" dictionary, retrieved from the API.
        time_base: The time to use as a reference.
        time_offset: A time offset to add.
        time_format: The time layout string to use or "relative".

    Returns:
        A definition of what to render.
    """
    time_planned = time_base + time_offset + int(departure.get("timeOffset", 0)) * time.minute
    time_actual = time_planned + int(departure.get("delay", 0)) * time.second

    return render.Row(
        expanded = True,
        main_align = "start",
        cross_align = "center",
        children = [
            render.Box(
                width = 18,
                height = 15,
                child = render_line_icon(departure["line"]),
            ),
            render.Column(
                children = [
                    render.Marquee(
                        width = 48,
                        child = render.Text(
                            content = departure["line"]["direction"],
                            height = 8,
                            font = "tb-8",
                        ),
                    ),
                    render.Marquee(
                        render_departure_time(time_format, time_base, time_planned, time_actual),
                        width = 48,
                    ),
                ],
            ),
        ],
    )

def render_message(message, color):
    """Render a message in a given color, below the HVV logo.

    Args:
        message: The message to show.
        color: The message color to use.

    Returns:
        A definition of what to render.
    """
    return render.Root(
        child = render.Box(
            color = COLOR_BACKGROUND,
            child = render.Column(
                children = [
                    render.Box(height = 16, child = render.Image(IMAGE_LOGO)),
                    render.Box(height = 16, child = render.WrappedText(
                        content = message,
                        font = "tom-thumb",
                        color = color,
                    )),
                ],
            ),
        ),
    )

def gti_request(method, data, ttl_seconds = GTI_API_CACHE_TTL_SECONDS):
    """Request the GTI (Geofox Thin Interface) API.

    Args:
        path: The method to request.
        data: The JSON request payload.

    Returns:
        A JSON response payload or `None`.
    """
    username = "**********"
    password = "**********"

    # Add method to API URL.
    url = GTI_API_URL.format(method = method)

    # Add API version to request payload.
    data.update({ "version": GTI_API_VERSION })

    # Serialize JSON request payload.
    body = json.encode(data)

    # Compute SHA1-HMAC signature of request payload and base64 encode it.
    signature = hmac.sha1(password, body, encoding = "base64")

    # Create dictionary of request headers.
    headers = {
        "geofox-auth-user": username,
        "geofox-auth-signature": signature,
        "content-type": "application/json",
    }

    # Send API request and cache it for a short time.
    response = http.post(
        url = url,
        headers = headers,
        body = body,
        ttl_seconds = ttl_seconds
    )

    if response.status_code != 200:
        print("API request failed with status %d" % response.status_code)
        return None

    return response.json()

def fetch_stations(query, max_results = 5):
    """Fetch stations matching a (fuzzy) query.

    Args:
        query: The (fuzzy) query string.
        max_results: Return at most this number of results.

    Returns:
        A list containing the stations.
    """
    response = gti_request(GTI_API_METHOD_CHECK_NAME, {
        "theName": {
            "name": query,
            "type": "STATION",
        },
        "maxList": max_results,
        "allowTypeSwitch": False,
    })

    return response.get("results", [])

def fetch_station_filters(station_id):
    """Fetch available filters (services) for the given station.

    Args:
        station_id: The station to fetch filters for.

    Returns:
        A tuple containing alist of filters (services) and a list of service types available at this station.
    """
    response = gti_request(GTI_API_METHOD_DEPARTURE_LIST, {
        "station": {
            "id": station_id,
            "type": "STATION",
        },
        "time": {},
        "maxList": 0,
        "returnFilters": True,
        "allStationsInChangingNode": True,
        "serviceTypes": []
    }, ttl_seconds = 300)

    filter = response.get("filter", [])
    service_types = response.get("serviceTypes", [])

    return (filter, service_types)

def fetch_departures(station_id, service_filter, service_types, time_when, time_offset, time_span, max_results = 2):
    """Fetch departures given a station identifier.

    Args:
        station_id: A station identifier to fetch departures for.
        service_filter: A service filter to filter departures for.
        service_types: A list of services types to filter departures for.
        time_when: A time to fetch departures for.
        time_offset: A time offset to add.
        time_span: A time span to search departures in.
        max_results: Return at most this number of results.

    Returns:
        A list containing the departures.
    """
    time_then = time_when + time_offset

    response = gti_request(GTI_API_METHOD_DEPARTURE_LIST, {
        "station": {
            "id": station_id,
            "type": "STATION",
        },
        "time": {
            "date": time_then.format(GTI_API_DATE_FORMAT),
            "time": time_then.format(GTI_API_TIME_FORMAT),
        },
        "filter": [service_filter] if service_filter else [],
        "maxTimeOffset": int(time_span.minutes),
        "maxList": max_results,
        "allStationsInChangingNode": True,
        "serviceTypes": service_types,
        "useRealtime": False
    })

    print(json.indent(json.encode(response.get("departures", []))))

    return response.get("departures", [])

def get_config_json(config, key, default = {}):
    """Get a JSON config option and decode it.

    Args:
        config: The applet configuration.
        key: The configuration key.
        default: The default value to fallback to.

    Returns:
        A decoded JSON object or the default value.
    """
    blob = config.str(key)
    return json.decode(blob) if blob != None else default

def get_config_json_value(config, key, json_key, default = None):
    """Get a JSON config option, decode it and retrieve a value using a key.

    Args:
        config: The applet configuration.
        key: The configuration key.
        json_key: The JSON key.
        default: The default value to fallback to.

    Returns:
        The value or the default value.
    """
    data = get_config_json(config, key)
    return data[json_key] if data != None and json_key in data else default

def parse_config(config):
    """Parse the applet configuration into some convenient structures.

    Args:
        config: The applet configuration.

    Returns:
        A tuple of transformed applet configuration values.
    """
    station_id = get_config_json_value(config, "station_id", "value", GTI_API_DEFAULT_STATION_ID)
    service_filter = get_config_json(config, "service_filter")
    time_format = config.str("time_format", "relative")
    time_offset = time.parse_duration(config.str("time_offset", "0m"))
    time_span = time.parse_duration(config.str("time_span", "2h"))
    service_types = flatten([
        OPTIONS_TO_GTI_API_SERVICE_TYPES[option]
        for option in OPTIONS_TO_GTI_API_SERVICE_TYPES
        if config.bool(option, True)
    ])

    return (station_id, service_filter, time_format, time_offset, time_span, service_types)

def main(config):
    """The applet entry point.

    Args:
        config: The applet configuration.

    Returns:
        A definition of what to render.
    """
    (station_id, service_filter, time_format, time_offset, time_span, service_types) = parse_config(config)

    # None of the service types are selected...
    if len(service_types) == 0:
        return render_message("Choose at least one service type", COLOR_MESSAGE_INFO)

    # Get current time and add configured offset.
    time_now = time.now()

    # Get time in correct timezone, which for Hamburg is "Europe/Berlin".
    time_in_location = time_now.in_location("Europe/Berlin")

    # Fetch departures and show an error message, if it fails.
    departures = fetch_departures(station_id, service_filter, service_types, time_in_location, time_offset, time_span)
    if departures == None:
        return render_message("Error fetching departures!", COLOR_MESSAGE_ERROR)

    # Slice departures to a maximum of two, although
    # it is already specified in the API request.
    departures = departures[0:2]

    # No departures were found...
    if len(departures) == 0:
        return render_message("Couldn't find any departures", COLOR_MESSAGE_INFO)

    return render.Root(
        child = render.Box(
            color = COLOR_BACKGROUND,
            child = render.Column(
                expanded = True,
                children = [
                    render_departure(departures[0], time_in_location, time_offset, time_format) if len(departures) > 0 else None,
                    render.Box(width = 64, height = 1, color = COLOR_SEPARATOR),
                    render_departure(departures[1], time_in_location, time_offset, time_format) if len(departures) > 1 else None,
                ],
            ),
        ),
    )

def find_stations(query):
    """Search the API for a list of stations matching a (fuzzy) query.

    Args:
        query: The (fuzzy) query string.

    Returns:
        A list of 'schema.Option', each corresponding to a station.
    """
    query = query.strip(" ")
    if len(query) == 0:
        return []

    stations = fetch_stations(query, 5)

    return [schema.Option(display = station["combinedName"], value = station["id"]) for station in stations]

def flatten(l):
    return [x for y in l for x in y]

def intersects(a, b):
    return any([x in a for x in b])

def get_station_fields(station_id):
    # A `Typeahead` value is actually a JSON blob...
    station_id = json.decode(station_id).get("value")

    # Fetch filters available for the given station.
    (filters, service_types) = fetch_station_filters(station_id)

    # List of fields to return.
    fields = []

    # Add a direction dropdown with available options.
    filter_options = [
        schema.Option(
            display = "All",
            value = OPTION_SERVICE_ALL,
        )
    ]

    filter_options.extend([
        schema.Option(
            display = "{} - {}".format(filter["serviceName"], filter["label"]),
            value = json.encode(filter),
        ) for filter in filters
    ])

    fields.append(
        schema.Dropdown(
            id = "service_filter",
            name = "Service",
            desc = "Pick a specific service",
            icon = "locationArrow",
            default = filter_options[0].value,
            options = filter_options,
        )
    )

    # Add toggles based on available service types.
    service_type_options = [
        toggle for toggle in
        [
            schema.Toggle(
                id = "include_subway",
                name = "U-Bahn",
                desc = "Include subways",
                icon = "trainSubway",
                default = True,
            ),
            schema.Toggle(
                id = "include_suburban",
                name = "S-Bahn",
                desc = "Include suburban trains",
                icon = "train",
                default = True,
            ),
            schema.Toggle(
                id = "include_bus",
                name = "Bus",
                desc = "Include buses",
                icon = "bus",
                default = True,
            ),
            schema.Toggle(
                id = "include_akn",
                name = "AKN",
                desc = "Include AKN commuter trains",
                icon = "train",
                default = True,
            ),
            schema.Toggle(
                id = "include_regional_train",
                name = "Regional",
                desc = "Include regional trains",
                icon = "train",
                default = True,
            ),
            schema.Toggle(
                id = "include_long_distance_train",
                name = "Long-distance",
                desc = "Include long-distance trains",
                icon = "train",
                default = True,
            ),
            schema.Toggle(
                id = "include_ferry",
                name = "Ferry",
                desc = "Include ferrys",
                icon = "ship",
                default = True,
            ),
        ]
        if intersects(OPTIONS_TO_GTI_API_SERVICE_TYPES[toggle.id], service_types)
    ]

    # Only add service type options if needed.
    if len(service_type_options) > 1:
        fields.extend(service_type_options)

    return fields

def get_schema():
    time_format_options = [
        schema.Option(
            display = "Relative",
            value = "relative",
        ),
        schema.Option(
            display = "Absolute (24h)",
            value = "15:04",
        ),
        schema.Option(
            display = "Absolute (12h)",
            value = "3:04 PM",
        ),
    ]

    time_offset_options = [
        schema.Option(
            display = "now",
            value = "0m",
        ),
        schema.Option(
            display = "in 5 minutes",
            value = "5m",
        ),
        schema.Option(
            display = "in 10 minutes",
            value = "10m",
        ),
        schema.Option(
            display = "in 15 minutes",
            value = "15m",
        ),
    ]

    time_span_options = [
        schema.Option(
            display = "30 minutes",
            value = "30m",
        ),
        schema.Option(
            display = "1 hour",
            value = "1h",
        ),
        schema.Option(
            display = "2 hours",
            value = "2h",
        ),
        schema.Option(
            display = "6 hours",
            value = "6h",
        ),
        schema.Option(
            display = "12 hours",
            value = "12h",
        ),
        schema.Option(
            display = "24 hours",
            value = "24h",
        ),
    ]

    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "auth_username",
                name = "Username",
                desc = "Geofox-API username.",
                icon = "user",
            ),
            schema.Text(
                id = "auth_password",
                name = "Password",
                desc = "Geofox-API password.",
                icon = "key",
            ),
            schema.Typeahead(
                id = "station_id",
                name = "Station",
                desc = "Pick a station",
                icon = "mapPin",
                handler = find_stations,
            ),
            schema.Generated(
                id = "generated",
                source = "station_id",
                handler = get_station_fields,
            ),
            schema.Dropdown(
                id = "time_format",
                name = "Time format",
                desc = "Pick a time format",
                icon = "clock",
                default = time_format_options[0].value,
                options = time_format_options,
            ),
            schema.Dropdown(
                id = "time_offset",
                name = "Time offset",
                desc = "Pick a time offset",
                icon = "plus",
                default = time_offset_options[0].value,
                options = time_offset_options,
            ),
            schema.Dropdown(
                id = "time_span",
                name = "Time span",
                desc = "Pick a time span",
                icon = "history",
                default = time_span_options[2].value,
                options = time_span_options,
            ),
        ],
    )

var poly1 = {
"type": "Feature",
"properties": {
    "fill": "#0f0"
},
"geometry": {
    "type": "Polygon",
    "coordinates": [[
    [-122.801742, 45.48565],
    [-122.801742, 45.60491],
    [-122.584762, 45.60491],
    [-122.584762, 45.48565],
    [-122.801742, 45.48565]
    ]]
}
}
var poly2 = {
"type": "Feature",
"properties": {
    "fill": "#00f"
},
"geometry": {
    "type": "Polygon",
    "coordinates": [[
    [-122.520217, 45.535693],
    [-122.64038, 45.553967],
    [-122.720031, 45.526554],
    [-122.669906, 45.507309],
    [-122.723464, 45.446643],
    [-122.532577, 45.408574],
    [-122.487258, 45.477466],
    [-122.520217, 45.535693]
    ]]
}
}

var polygons = {
"type": "FeatureCollection",
"features": [poly1, poly2]
};

var intersection = turf.intersect(poly1, poly2);
console.log(intersection);
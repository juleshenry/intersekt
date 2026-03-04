from turfpy.transformation import intersect
from turfpy.measurement import area
from geojson import Feature
from polysekt import PolygonClipper
import numpy as np

xyz = [[[0, 0], [0, 1], [1, 1], [1, 0], [0, 0]]]
a = Feature(geometry={"coordinates": xyz, "type": "Polygon",})
b = Feature(geometry={"coordinates": xyz, "type": "Polygon",})
inter = intersect([a, b])

sqr = xyz
easy_square = Feature(geometry={"coordinates": sqr, "type": "Polygon",})
print("Area of easy square in turfjs ", area(easy_square))


a, b = map(np.array, (a, b,))
# clipped_polygon = clip(a, b)
# print(clipped_polygon)

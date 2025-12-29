from polysekt import PolygonClipper
from turfpy.transformation import intersect
from turfpy.measurement import area
from geojson import Feature
import numpy as np

xyz = [[[0, 0], [0, 1], [1, 1], [1, 0], [0, 0]]]
a = Feature(geometry={"coordinates": xyz, "type": "Polygon",})
b = Feature(geometry={"coordinates": xyz, "type": "Polygon",})
inter = intersect([a, b])
print("Geo Inter: ", inter)
# print(area(inter))

clip = PolygonClipper()
a = xyz[0]
b = xyz[0]
inter = clip(*map(np.array, [a, b]))
inter = inter.tolist()

c_inter = Feature(geometry={"coordinates": [inter], "type": "Polygon"})
print(c_inter)
print("Polygon Inter: ", c_inter)
# print(area(c_inter))

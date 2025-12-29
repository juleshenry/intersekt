

export function winning(clipPolygon, subjectPolygon) {
    console.log('Wintersekt called...');
    let result = turf.intersect(clipPolygon, subjectPolygon);
    // let result = subjectPolygon;
    console.log(result);
    return result;
}

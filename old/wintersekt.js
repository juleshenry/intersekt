import { intersect, polygon } from 'https://cdnjs.cloudflare.com/ajax/libs/Turf.js/0.0.124/turf.js';
function wintersekt(clipPolygon, subjectPolygon) {
    console.log('Winter sekt');
    let result = intersect(clipPolygon,subjectPolygon);
    // let result = subjectPolygon;
    console.log(result);
    return result;
}
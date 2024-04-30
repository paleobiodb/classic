

function PBDB_map_widget(mapElementName, options) {
    this.marker_layer = new ol.Feature({
      geometry: new ol.geom.Point([0, 0])
    });

    var iconStyle = new ol.style.Style(({
      anchor: [10, 25],
      anchorXUnits: 'pixels',
      anchorYUnits: 'pixels',
      image: new ol.style.Icon({
        src: '/JavaScripts/img/marker.png',
      })
    }));

    this.marker_layer.setStyle(iconStyle);

    var vectorSource = new ol.source.Vector({
      features: [this.marker_layer]
    });

    var vectorLayer = new ol.layer.Vector({
      source: vectorSource
    });

    var attribution = new ol.Attribution({
      html: '© OpenStreetMap contributors, © CARTO'
    });

    // First, create an OpenLayers map, plus a baselayer and some default
    // controls.
    var map = new ol.Map({
        target: mapElementName,
        layers: [
          new ol.layer.Tile({
            source: new ol.source.XYZ({
              attributions: [attribution],
              url: 'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png'
            })
          }),
          vectorLayer
        ],
        view: new ol.View({
          center: ol.proj.fromLonLat([0, 0]),
          zoom: 3
        })
      });

    this.deactivateMarker = function() {
      if (this.marker_layer) {
        vectorSource.removeFeature(this.marker_layer);
      }
    }

    this.setMarker = function( lng, lat ) {
      this.deactivateMarker();

      vectorSource.addFeature(this.marker_layer);
      this.marker_layer.setGeometry(new ol.geom.Point(ol.proj.transform([lng, lat], 'EPSG:4326',
  'EPSG:3857')));
    }

    this.showMarker = function( center ) {
      map.setView(new ol.View({
        center: ol.proj.fromLonLat(ol.proj.transform(this.marker_layer.getGeometry().getCoordinates(), 'EPSG:3857', 'EPSG:4326')),
        zoom: 10
      }))
    }

    this.updateSize = function() {
      map.updateSize()
    }

    map.on('singleclick', function( event ) {
      var newCoord = new ol.geom.Point(event.coordinate);
      this.marker_layer.setGeometry(newCoord);

      if (options.click_callback) {
        var lnglat = ol.proj.transform(event.coordinate, 'EPSG:3857', 'EPSG:4326')
        options.click_callback(lnglat[1], lnglat[0]);
      }
    }.bind(this));

    setTimeout(function() {
      map.updateSize();
    }, 3000);

}

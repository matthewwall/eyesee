// default values for eyesee web interface

var CFG = {
    "server_url": "/cgi-bin/info",
    "max_age": 1, // days - how many days to display in single page
    "type": 'img', // img or vid
    "camera": "garage", // default camera
    "cameras": [
        { "camera_id": 'x.x.x.x', "camera_label": 'porch' },
        { "camera_id": 'y.y.y.y', "camera_label": 'driveway' },
        { "camera_id": 'z.z.z.z', "camera_label": 'garage' }
    ]
};

from django.http import FileResponse, HttpResponse, HttpResponseNotAllowed
from django.views.decorators.csrf import csrf_exempt

from pipeline.queues import get_pipeline
from pipeline.storage import new_request_timestamp, team_dir_from_filename, validate_team_dir


@csrf_exempt
def endpoint(request):
    if request.method == "POST":
        return accept_osm(request)
    if request.method == "GET":
        return fetch_result(request)
    return HttpResponseNotAllowed(["GET", "POST"])


def accept_osm(request):
    upload = request.FILES.get("file")
    if upload is None:
        return HttpResponse("expected file field with a .osm upload", status=400)
    try:
        team_dir = team_dir_from_filename(upload.name)
    except ValueError as exc:
        return HttpResponse(str(exc), status=400)
    request_timestamp = new_request_timestamp()
    get_pipeline().storage.save_osm(team_dir, request_timestamp, upload.name, upload.read())
    get_pipeline().enqueue_matsim(request_timestamp, team_dir)
    return HttpResponse(status=200)


def fetch_result(request):
    raw = request.GET.get("team_dir", "")
    try:
        team_dir = validate_team_dir(raw)
    except ValueError:
        return HttpResponse(status=404)
    path = get_pipeline().storage.latest_zip(team_dir)
    if path is None:
        return HttpResponse(status=404)
    handle = path.open("rb")
    return FileResponse(handle, as_attachment=True, filename=path.name)

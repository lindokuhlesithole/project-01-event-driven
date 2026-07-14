import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def log_event(event_type, data):
    logger.info(json.dumps({
        "event_type": event_type,
        "data": data
    }))

from fastapi import FastAPI, Depends, HTTPException, status, Body, UploadFile, File, Form, Request, BackgroundTasks
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional, Dict, Any, Union
from datetime import datetime, timedelta
from jose import JWTError, jwt
from passlib.context import CryptContext
from motor.motor_asyncio import AsyncIOMotorClient
from bson import ObjectId
import os
import socket
from dotenv import load_dotenv
import shutil
import uuid
from pathlib import Path
from fastapi.staticfiles import StaticFiles
import logging

# Firebase imports (make sure to install firebase-admin)
try:
    import firebase_admin
    from firebase_admin import credentials, messaging
    firebase_available = True
except ImportError:
    firebase_available = False
    logging.warning("Firebase Admin SDK not installed. Push notifications will be disabled.")

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load environment variables
load_dotenv()

# MongoDB connection
MONGODB_URL = os.getenv("MONGODB_URL", "mongodb://localhost:27017")
client = AsyncIOMotorClient(MONGODB_URL)
db = client.learnlive

# File upload settings
UPLOAD_DIR = "uploads"
Path(UPLOAD_DIR).mkdir(exist_ok=True)

# JWT settings
SECRET_KEY = os.getenv("SECRET_KEY", "your-very-secret-key-123")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24  # 24 hours

# Password hashing
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# OAuth2 scheme
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

app = FastAPI(title="LearnLive API")

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Models
class UserBase(BaseModel):
    email: str
    name: str
    role: str
    class_level: Optional[str] = None

class UserCreate(UserBase):
    password: str

class User(UserBase):
    id: str
    created_at: datetime

    class Config:
        from_attributes = True

class Token(BaseModel):
    access_token: str
    token_type: str

class TokenData(BaseModel):
    email: Optional[str] = None

class CourseBase(BaseModel):
    title: str
    description: str
    grade: str
    price: float
    video_url: Optional[str] = None

class CourseCreate(CourseBase):
    pass

class Course(CourseBase):
    id: str
    teacher_id: str
    teacher_name: str
    students: Optional[List[str]] = []
    thumbnail: Optional[str] = None
    modules: Optional[List[str]] = []
    created_at: datetime

    class Config:
        from_attributes = True

class SessionBase(BaseModel):
    title: str
    description: str
    module_id: Optional[str] = None
    course: Optional[str] = None
    date: str
    time: str
    duration: int
    teacher: str

class SessionCreate(SessionBase):
    pass

class Session(SessionBase):
    id: str
    meeting_link: Optional[str] = None
    recording_link: Optional[str] = None
    attendees: Optional[List[str]] = []

    class Config:
        from_attributes = True

class PaymentRequest(BaseModel):
    course_id: str
    amount: float
    payment_method: Optional[str] = "card"
    card_details: Optional[Dict[str, Any]] = None

class PaymentResponse(BaseModel):
    payment_id: str
    status: str
    message: str
    transaction_date: datetime
    course_id: str
    amount: float

class CourseMaterialBase(BaseModel):
    title: str
    description: str
    type: str  # 'note', 'pdf', 'video', 'link', etc.

class CourseMaterialCreate(CourseMaterialBase):
    content: Optional[str] = None
    file_url: Optional[str] = None
    external_url: Optional[str] = None

class CourseMaterial(CourseMaterialBase):
    id: str
    course_id: str
    content: Optional[str] = None
    file_url: Optional[str] = None
    external_url: Optional[str] = None
    created_at: datetime
    created_by: str
    file_name: Optional[str] = None
    file_size: Optional[int] = None

    class Config:
        from_attributes = True

class NotificationBase(BaseModel):
    title: str
    message: str
    user_id: str
    image_url: Optional[str] = None
    action_type: Optional[str] = None  # 'course', 'session', 'payment', etc.
    action_id: Optional[str] = None  # ID related to the action (courseId, sessionId, etc.)

class NotificationCreate(NotificationBase):
    pass

class Notification(NotificationBase):
    id: str
    created_at: datetime
    is_read: bool = False

    class Config:
        from_attributes = True

class DeviceToken(BaseModel):
    device_token: str
    device_type: str  # 'android' or 'ios'

# Initialize Firebase Admin SDK if available
firebase_enabled = False
if firebase_available:
    try:
        cred = credentials.Certificate("serviceAccountKey.json")
        firebase_admin.initialize_app(cred)
        firebase_enabled = True
    except Exception as e:
        logger.error(f"Firebase initialization error: {str(e)}")
        firebase_enabled = False

# Helper functions
def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password):
    return pwd_context.hash(password)

async def get_user(email: str):
    user = await db.users.find_one({"email": email})
    if user:
        user["id"] = str(user["_id"])
        return user
    return None

async def authenticate_user(email: str, password: str):
    user = await get_user(email)
    if not user:
        return False
    if not verify_password(password, user["password"]):
        return False
    return user

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

async def get_current_user(token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        email: str = payload.get("sub")
        if email is None:
            raise credentials_exception
        token_data = TokenData(email=email)
    except JWTError:
        raise credentials_exception
    user = await get_user(email=token_data.email)
    if user is None:
        raise credentials_exception
    return user

async def send_push_notification(
    user_id: str,
    title: str,
    body: str,
    data: Optional[Dict[str, str]] = None
):
    if not firebase_enabled:
        logger.warning("Firebase is not initialized, skipping push notification")
        return
    
    try:
        # Get user's device tokens
        device_tokens = []
        async for token_doc in db.device_tokens.find({"user_id": user_id}):
            device_tokens.append(token_doc["device_token"])
        
        if not device_tokens:
            logger.info(f"No device tokens found for user {user_id}")
            return
        
        # Create message
        message = messaging.MulticastMessage(
            tokens=device_tokens,
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            data=data or {},
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    icon="ic_launcher",
                    color="#8852E5",
                    sound="default",
                ),
            ),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(
                        sound="default",
                    ),
                ),
            ),
        )
        
        # Send message
        response = messaging.send_multicast(message)
        logger.info(f"Push notification sent to {response.success_count} devices")
        
        # Handle failures
        if response.failure_count > 0:
            for idx, resp in enumerate(response.responses):
                if not resp.success:
                    logger.error(f"Failed to send notification to {device_tokens[idx]}: {resp.exception}")
                    
                    # Remove invalid tokens
                    if "invalid-argument" in str(resp.exception) or "not-registered" in str(resp.exception):
                        await db.device_tokens.delete_one({"device_token": device_tokens[idx]})
    
    except Exception as e:
        logger.error(f"Error sending push notification: {str(e)}")

async def create_notification(notification_data: dict):
    notification_data["created_at"] = datetime.utcnow()
    notification_data["is_read"] = False
    
    result = await db.notifications.insert_one(notification_data)
    notification_id = str(result.inserted_id)
    
    # Send push notification
    user_id = notification_data["user_id"]
    title = notification_data["title"]
    message = notification_data["message"]
    
    data = {}
    if "action_type" in notification_data:
        data["action_type"] = notification_data["action_type"]
    if "action_id" in notification_data:
        data["action_id"] = notification_data["action_id"]
    
    await send_push_notification(user_id, title, message, data)
    
    return notification_id

# Routes
@app.post("/token", response_model=Token)
async def login_for_access_token(form_data: OAuth2PasswordRequestForm = Depends()):
    user = await authenticate_user(form_data.username, form_data.password)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user["email"]}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}

@app.post("/users", response_model=User)
async def create_user(user: UserCreate, background_tasks: BackgroundTasks):
    db_user = await get_user(user.email)
    if db_user:
        raise HTTPException(status_code=400, detail="Email already registered")
    
    hashed_password = get_password_hash(user.password)
    user_dict = user.dict()
    user_dict.pop("password")
    user_dict["password"] = hashed_password
    user_dict["created_at"] = datetime.utcnow()
    
    result = await db.users.insert_one(user_dict)
    user_id = str(result.inserted_id)
    user_dict["id"] = user_id
    
    # Create welcome notification
    notification_data = {
        "user_id": user_id,
        "title": "Welcome to LearnLive!",
        "message": f"Welcome {user.name}! We're excited to have you join our platform.",
        "action_type": "welcome",
    }
    background_tasks.add_task(create_notification, notification_data)
    
    return user_dict

@app.get("/users/me", response_model=User)
async def read_users_me(current_user: dict = Depends(get_current_user)):
    current_user["id"] = str(current_user["_id"])
    return current_user

@app.put("/users/me/class")
async def update_class_level(
    current_user: dict = Depends(get_current_user),
    class_data: dict = Body(...),
    background_tasks: BackgroundTasks = BackgroundTasks()
):
    if current_user["role"] != "student":
        raise HTTPException(status_code=400, detail="Only students can update class level")
    
    await db.users.update_one(
        {"_id": ObjectId(current_user["_id"])},
        {"$set": {"class_level": class_data["class_level"]}}
    )
    
    updated_user = await db.users.find_one({"_id": ObjectId(current_user["_id"])})
    updated_user["id"] = str(updated_user["_id"])
    
    # Create notification for class level update
    notification_data = {
        "user_id": str(current_user["_id"]),
        "title": "Class Level Updated",
        "message": f"Your class level has been updated to Grade {class_data['class_level']}.",
        "action_type": "profile_update",
    }
    background_tasks.add_task(create_notification, notification_data)
    
    return updated_user

@app.get("/courses", response_model=List[Course])
async def get_courses(
    current_user: dict = Depends(get_current_user),
    grade: Optional[str] = None
):
    query = {}
    if grade:
        query["grade"] = grade
    
    courses = []
    async for course in db.courses.find(query):
        course["id"] = str(course["_id"])
        courses.append(course)
    return courses

@app.get("/courses/{course_id}", response_model=Course)
async def get_course(course_id: str, current_user: dict = Depends(get_current_user)):
    if not ObjectId.is_valid(course_id):
        raise HTTPException(status_code=400, detail="Invalid course ID format")
    
    course = await db.courses.find_one({"_id": ObjectId(course_id)})
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")
    
    course["id"] = str(course["_id"])
    return course

@app.get("/course/enrolled", response_model=List[Course])
async def get_enrolled_courses(current_user: dict = Depends(get_current_user)):
    user_id = str(current_user["_id"])
    
    courses = []
    async for course in db.courses.find({"students": user_id}):
        course["id"] = str(course["_id"])
        courses.append(course)
    
    return courses

@app.post("/courses", response_model=Course)
async def create_course(
    current_user: dict = Depends(get_current_user),
    title: str = Form(...),
    description: str = Form(...),
    grade: str = Form(...),
    price: float = Form(...),
    video: Optional[UploadFile] = File(None),
    background_tasks: BackgroundTasks = BackgroundTasks()
):
    if current_user["role"] != "teacher":
        raise HTTPException(status_code=400, detail="Only teachers can create courses")
    
    video_url = None
    if video:
        try:
            file_ext = video.filename.split(".")[-1] if "." in video.filename else ""
            unique_filename = f"{uuid.uuid4()}.{file_ext}"
            file_path = os.path.join(UPLOAD_DIR, unique_filename)
            
            with open(file_path, "wb") as buffer:
                shutil.copyfileobj(video.file, buffer)
            
            video_url = f"/uploads/{unique_filename}"
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Error saving video: {str(e)}")
    
    course_dict = {
        "title": title,
        "description": description,
        "grade": grade,
        "price": price,
        "teacher_id": str(current_user["_id"]),
        "teacher_name": current_user["name"],
        "students": [],
        "created_at": datetime.utcnow(),
        "video_url": video_url
    }
    
    result = await db.courses.insert_one(course_dict)
    course_id = str(result.inserted_id)
    course_dict["id"] = course_id
    
    # Create notification for the teacher
    notification_data = {
        "user_id": str(current_user["_id"]),
        "title": "Course Created",
        "message": f"Your course '{title}' has been created successfully.",
        "action_type": "course",
        "action_id": course_id,
    }
    background_tasks.add_task(create_notification, notification_data)
    
    # Create notifications for students in the appropriate grade
    async for student in db.users.find({"role": "student", "class_level": grade}):
        student_notification = {
            "user_id": str(student["_id"]),
            "title": "New Course Available",
            "message": f"A new course '{title}' for Grade {grade} is now available.",
            "action_type": "course",
            "action_id": course_id,
        }
        background_tasks.add_task(create_notification, student_notification)
    
    return course_dict

@app.post("/courses/{course_id}/enroll")
async def enroll_in_course(
    course_id: str,
    current_user: dict = Depends(get_current_user),
    background_tasks: BackgroundTasks = BackgroundTasks()
):
    user_id = str(current_user["_id"])
    
    if not ObjectId.is_valid(course_id):
        raise HTTPException(status_code=400, detail="Invalid course ID format")
    
    course = await db.courses.find_one({"_id": ObjectId(course_id)})
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")
    
    if "students" in course and user_id in course["students"]:
        raise HTTPException(status_code=400, detail="Already enrolled in this course")
    
    await db.courses.update_one(
        {"_id": ObjectId(course_id)},
        {"$push": {"students": user_id}}
    )
    
    # Create notification for the student
    student_notification = {
        "user_id": user_id,
        "title": "Course Enrollment Successful",
        "message": f"You have successfully enrolled in '{course['title']}'.",
        "action_type": "course",
        "action_id": course_id,
    }
    background_tasks.add_task(create_notification, student_notification)
    
    # Create notification for the teacher
    teacher_notification = {
        "user_id": course["teacher_id"],
        "title": "New Student Enrolled",
        "message": f"{current_user['name']} has enrolled in your course '{course['title']}'.",
        "action_type": "course",
        "action_id": course_id,
    }
    background_tasks.add_task(create_notification, teacher_notification)
    
    return {"message": "Successfully enrolled in course"}

@app.post("/payments", response_model=PaymentResponse)
async def process_payment(
    current_user: dict = Depends(get_current_user),
    payment: PaymentRequest = Body(...),
    background_tasks: BackgroundTasks = BackgroundTasks()
):
    if not ObjectId.is_valid(payment.course_id):
        raise HTTPException(status_code=400, detail="Invalid course ID format")
    
    course = await db.courses.find_one({"_id": ObjectId(payment.course_id)})
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")
    
    payment_id = str(ObjectId())
    
    payment_record = {
        "payment_id": payment_id,
        "user_id": str(current_user["_id"]),
        "course_id": payment.course_id,
        "amount": payment.amount,
        "status": "success",
        "payment_method": payment.payment_method,
        "transaction_date": datetime.utcnow()
    }
    
    await db.payments.insert_one(payment_record)
    
    user_id = str(current_user["_id"])
    if user_id not in course.get("students", []):
        await db.courses.update_one(
            {"_id": ObjectId(payment.course_id)},
            {"$push": {"students": user_id}}
        )
    
    # Create payment notification for the student
    student_notification = {
        "user_id": user_id,
        "title": "Payment Successful",
        "message": f"Your payment of ${payment.amount} for '{course['title']}' was successful.",
        "action_type": "payment",
    }
    background_tasks.add_task(create_notification, student_notification)
    
    # Create enrollment notification for the teacher
    teacher_notification = {
        "user_id": course["teacher_id"],
        "title": "New Payment Received",
        "message": f"{current_user['name']} has made a payment of ${payment.amount} for '{course['title']}'.",
        "action_type": "payment",
    }
    background_tasks.add_task(create_notification, teacher_notification)
    
    return {
        "payment_id": payment_id,
        "status": "success",
        "message": "Payment processed successfully",
        "transaction_date": datetime.utcnow(),
        "course_id": payment.course_id,
        "amount": payment.amount
    }

# Add a DELETE endpoint for courses
@app.delete("/courses/{course_id}")
async def delete_course(
    course_id: str,
    current_user: dict = Depends(get_current_user),
    background_tasks: BackgroundTasks = BackgroundTasks()
):
    if not ObjectId.is_valid(course_id):
        raise HTTPException(status_code=400, detail="Invalid course ID format")
    
    course = await db.courses.find_one({"_id": ObjectId(course_id)})
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")
    
    user_id = str(current_user["_id"])
    if course.get("teacher_id") != user_id:
        raise HTTPException(
            status_code=403, 
            detail="Only the course teacher can delete this course"
        )
    
    # Delete all materials associated with the course
    await db.course_materials.delete_many({"course_id": course_id})
    
    # Delete all sessions associated with the course
    await db.sessions.delete_many({"course_id": course_id})
    
    # Delete the course
    result = await db.courses.delete_one({"_id": ObjectId(course_id)})
    
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Course not found")
    
    # Create notification for the teacher
    notification_data = {
        "user_id": user_id,
        "title": "Course Deleted",
        "message": f"Your course '{course['title']}' has been deleted successfully.",
        "action_type": "course_deleted",
    }
    background_tasks.add_task(create_notification, notification_data)
    
    # Create notifications for enrolled students
    for student_id in course.get("students", []):
        student_notification = {
            "user_id": student_id,
            "title": "Course Removed",
            "message": f"The course '{course['title']}' has been removed.",
            "action_type": "course_deleted",
        }
        background_tasks.add_task(create_notification, student_notification)
    
    return {"message": "Course deleted successfully"}

# Add a PUT endpoint to update courses
@app.put("/courses/{course_id}", response_model=Course)
async def update_course(
    course_id: str,
    current_user: dict = Depends(get_current_user),
    title: str = Form(...),
    description: str = Form(...),
    grade: str = Form(...),
    price: float = Form(...),
    video: Optional[UploadFile] = File(None),
    background_tasks: BackgroundTasks = BackgroundTasks()
):
    if not ObjectId.is_valid(course_id):
        raise HTTPException(status_code=400, detail="Invalid course ID format")
    
    course = await db.courses.find_one({"_id": ObjectId(course_id)})
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")
    
    user_id = str(current_user["_id"])
    if course.get("teacher_id") != user_id:
        raise HTTPException(
            status_code=403, 
            detail="Only the course teacher can update this course"
        )
    
    video_url = course.get("video_url")
    if video:
        try:
            # Delete old video if exists
            if video_url:
                old_video_path = video_url.lstrip("/")
                if os.path.exists(old_video_path):
                    os.remove(old_video_path)
            
            # Save new video
            file_ext = video.filename.split(".")[-1] if "." in video.filename else ""
            unique_filename = f"{uuid.uuid4()}.{file_ext}"
            file_path = os.path.join(UPLOAD_DIR, unique_filename)
            
            with open(file_path, "wb") as buffer:
                shutil.copyfileobj(video.file, buffer)
            
            video_url = f"/uploads/{unique_filename}"
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Error saving video: {str(e)}")
    
    # Update the course
    await db.courses.update_one(
        {"_id": ObjectId(course_id)},
        {"$set": {
            "title": title,
            "description": description,
            "grade": grade,
            "price": price,
            "video_url": video_url,
            "updated_at": datetime.utcnow()
        }}
    )
    
    # Get the updated course
    updated_course = await db.courses.find_one({"_id": ObjectId(course_id)})
    updated_course["id"] = str(updated_course["_id"])
    
    # Create notification for the teacher
    notification_data = {
        "user_id": user_id,
        "title": "Course Updated",
        "message": f"Your course '{updated_course['title']}' has been updated successfully.",
        "action_type": "course",
        "action_id": course_id,
    }
    background_tasks.add_task(create_notification, notification_data)
    
    # Create notifications for enrolled students
    for student_id in updated_course.get("students", []):
        student_notification = {
            "user_id": student_id,
            "title": "Course Updated",
            "message": f"The course '{updated_course['title']}' has been updated.",
            "action_type": "course",
            "action_id": course_id,
        }
        background_tasks.add_task(create_notification, student_notification)
    
    return updated_course

# Course Materials Endpoints
@app.get("/courses/{course_id}/materials", response_model=List[CourseMaterial])
async def get_course_materials(
    course_id: str,
    current_user: dict = Depends(get_current_user)
):
    if not ObjectId.is_valid(course_id):
        raise HTTPException(status_code=400, detail="Invalid course ID format")
    
    course = await db.courses.find_one({"_id": ObjectId(course_id)})
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")
    
    user_id = str(current_user["_id"])
    is_teacher = current_user["role"] == "teacher"
    is_course_teacher = course.get("teacher_id") == user_id
    is_enrolled = user_id in course.get("students", [])
    
    if not (is_teacher or is_course_teacher or is_enrolled):
        raise HTTPException(
            status_code=403, 
            detail="You must be the teacher or enrolled in the course to view materials"
        )
    
    materials = []
    async for material in db.course_materials.find({"course_id": course_id}).sort("created_at", -1):
        material["id"] = str(material["_id"])
        materials.append(material)
    
    return materials

@app.post("/courses/{course_id}/materials", response_model=CourseMaterial)
async def create_course_material(
    course_id: str,
    current_user: dict = Depends(get_current_user),
    title: str = Form(...),
    description: str = Form(...),
    type: str = Form(...),
    content: Optional[str] = Form(None),
    external_url: Optional[str] = Form(None),
    file: Optional[UploadFile] = File(None),
    background_tasks: BackgroundTasks = BackgroundTasks()
):
    logger.info(f"Creating material for course {course_id}")
    
    if not ObjectId.is_valid(course_id):
        raise HTTPException(status_code=400, detail="Invalid course ID format")
    
    course = await db.courses.find_one({"_id": ObjectId(course_id)})
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")
    
    user_id = str(current_user["_id"])
    if course.get("teacher_id") != user_id:
        raise HTTPException(
            status_code=403, 
            detail="Only the course teacher can add materials"
        )
    
    file_url = None
    file_name = None
    file_size = None
    
    if file:
        try:
            file_ext = file.filename.split(".")[-1] if "." in file.filename else ""
            unique_filename = f"{uuid.uuid4()}.{file_ext}"
            file_path = os.path.join(UPLOAD_DIR, unique_filename)
            
            with open(file_path, "wb") as buffer:
                shutil.copyfileobj(file.file, buffer)
            
            file_url = f"/uploads/{unique_filename}"
            file_name = file.filename
            file_size = os.path.getsize(file_path)
            
            if not type:
                if file_ext.lower() in ["pdf", "doc", "docx"]:
                    type = "document"
                elif file_ext.lower() in ["jpg", "jpeg", "png", "gif"]:
                    type = "image"
                elif file_ext.lower() in ["mp4", "mov", "avi"]:
                    type = "video"
                else:
                    type = "file"
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Error saving file: {str(e)}")
    
    material_dict = {
        "title": title,
        "description": description,
        "type": type,
        "content": content,
        "external_url": external_url,
        "file_url": file_url,
        "file_name": file_name,
        "file_size": file_size,
        "course_id": course_id,
        "created_at": datetime.utcnow(),
        "created_by": user_id
    }
    
    result = await db.course_materials.insert_one(material_dict)
    material_id = str(result.inserted_id)
    material_dict["id"] = material_id
    
    # Create notification for the teacher
    teacher_notification = {
        "user_id": user_id,
        "title": "Material Added",
        "message": f"You've successfully added '{title}' to '{course['title']}'.",
        "action_type": "material",
        "action_id": material_id,
    }
    background_tasks.add_task(create_notification, teacher_notification)
    
    # Create notifications for enrolled students
    for student_id in course.get("students", []):
        student_notification = {
            "user_id": student_id,
            "title": "New Course Material",
            "message": f"New material '{title}' has been added to '{course['title']}'.",
            "action_type": "material",
            "action_id": material_id,
        }
        background_tasks.add_task(create_notification, student_notification)
    
    return material_dict

@app.get("/courses/{course_id}/materials/{material_id}", response_model=CourseMaterial)
async def get_course_material(
    course_id: str,
    material_id: str,
    current_user: dict = Depends(get_current_user)
):
    if not ObjectId.is_valid(course_id) or not ObjectId.is_valid(material_id):
        raise HTTPException(status_code=400, detail="Invalid ID format")
    
    course = await db.courses.find_one({"_id": ObjectId(course_id)})
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")
    
    user_id = str(current_user["_id"])
    is_teacher = current_user["role"] == "teacher"
    is_course_teacher = course.get("teacher_id") == user_id
    is_enrolled = user_id in course.get("students", [])
    
    if not (is_teacher or is_course_teacher or is_enrolled):
        raise HTTPException(
            status_code=403, 
            detail="You must be the teacher or enrolled in the course to view this material"
        )
    
    material = await db.course_materials.find_one({
        "_id": ObjectId(material_id),
        "course_id": course_id
    })
    
    if not material:
        raise HTTPException(status_code=404, detail="Material not found")
    
    material["id"] = str(material["_id"])
    return material

@app.delete("/courses/{course_id}/materials/{material_id}")
async def delete_course_material(
    course_id: str,
    material_id: str,
    current_user: dict = Depends(get_current_user)
):
    if not ObjectId.is_valid(course_id) or not ObjectId.is_valid(material_id):
        raise HTTPException(status_code=400, detail="Invalid ID format")
    
    course = await db.courses.find_one({"_id": ObjectId(course_id)})
    if not course:
        raise HTTPException(status_code=404, detail="Course not found")
    
    user_id = str(current_user["_id"])
    if course.get("teacher_id") != user_id:
        raise HTTPException(
            status_code=403, 
            detail="Only the course teacher can delete materials"
        )
    
    material = await db.course_materials.find_one({
        "_id": ObjectId(material_id),
        "course_id": course_id
    })
    
    if not material:
        raise HTTPException(status_code=404, detail="Material not found")
    
    if material.get("file_url"):
        try:
            file_path = material["file_url"].lstrip("/")
            if os.path.exists(file_path):
                os.remove(file_path)
        except Exception as e:
            logger.error(f"Error deleting file: {str(e)}")
    
    result = await db.course_materials.delete_one({
        "_id": ObjectId(material_id),
        "course_id": course_id
    })
    
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Material not found")
    
    return {"message": "Material deleted successfully"}

# Sessions Endpoints
@app.get("/sessions/upcoming", response_model=List[Session])
async def get_upcoming_sessions(current_user: dict = Depends(get_current_user)):
    user_id = str(current_user["_id"])
    today = datetime.utcnow().strftime("%Y-%m-%d")
    
    query = {}
    if current_user["role"] == "student":
        enrolled_courses = []
        async for course in db.courses.find({"students": user_id}):
            enrolled_courses.append(str(course["_id"]))
            enrolled_courses.append(course["title"])
        
        query = {
            "date": {"$gte": today},
            "$or": [
                {"course_id": {"$in": enrolled_courses}},
                {"course": {"$in": enrolled_courses}}
            ]
        }
    else:
        query = {
            "date": {"$gte": today},
            "teacher_id": user_id
        }
    
    sessions = []
    async for session in db.sessions.find(query).sort("date", 1).sort("time", 1):
        session["id"] = str(session["_id"])
        sessions.append(session)
    
    return sessions

@app.post("/sessions", response_model=Session)
async def create_session(
    current_user: dict = Depends(get_current_user),
    session: SessionCreate = Body(...),
    background_tasks: BackgroundTasks = BackgroundTasks()
):
    if current_user["role"] != "teacher":
        raise HTTPException(status_code=400, detail="Only teachers can create sessions")
    
    session_dict = session.dict()
    session_dict["teacher_id"] = str(current_user["_id"])
    session_dict["attendees"] = []
    session_dict["meeting_link"] = f"https://meet.jit.si/learnlive-session-{ObjectId()}"
    
    result = await db.sessions.insert_one(session_dict)
    session_id = str(result.inserted_id)
    session_dict["id"] = session_id
    
    # Create notification for the teacher
    teacher_notification = {
        "user_id": str(current_user["_id"]),
        "title": "Session Created",
        "message": f"You've scheduled a new session '{session.title}' on {session.date} at {session.time}.",
        "action_type": "session",
        "action_id": session_id,
    }
    background_tasks.add_task(create_notification, teacher_notification)
    
    # Find the course and notify enrolled students
    if session.course:
        course = None
        # Try to find by ID first
        if ObjectId.is_valid(session.course):
            course = await db.courses.find_one({"_id": ObjectId(session.course)})
        
        # If not found, try to find by title
        if not course:
            course = await db.courses.find_one({"title": session.course})
        
        if course:
            for student_id in course.get("students", []):
                student_notification = {
                    "user_id": student_id,
                    "title": "New Live Session Scheduled",
                    "message": f"A new session '{session.title}' has been scheduled for {session.date} at {session.time}.",
                    "action_type": "session",
                    "action_id": session_id,
                }
                background_tasks.add_task(create_notification, student_notification)
    
    return session_dict

@app.get("/sessions/{session_id}", response_model=Session)
async def get_session(
    session_id: str,
    current_user: dict = Depends(get_current_user)
):
    session = await db.sessions.find_one({"_id": ObjectId(session_id)})
    
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    session["id"] = str(session["_id"])
    
    if current_user["role"] == "student":
        enrolled_courses = []
        async for course in db.courses.find({"students": str(current_user["_id"])}):
            enrolled_courses.append(str(course["_id"]))
            enrolled_courses.append(course["title"])
        
        if session.get("course_id") not in enrolled_courses and session.get("course") not in enrolled_courses:
            raise HTTPException(
                status_code=403, 
                detail="You must be enrolled in the course to access this session"
            )
    
    return session

# Notification Endpoints
@app.get("/notifications", response_model=List[Notification])
async def get_notifications(current_user: dict = Depends(get_current_user)):
    user_id = str(current_user["_id"])
    
    notifications = []
    async for notification in db.notifications.find({"user_id": user_id}).sort("created_at", -1):
        notification["id"] = str(notification["_id"])
        notifications.append(notification)
    
    return notifications

@app.put("/notifications/{notification_id}/read")
async def mark_notification_as_read(
    notification_id: str,
    current_user: dict = Depends(get_current_user)
):
    if not ObjectId.is_valid(notification_id):
        raise HTTPException(status_code=400, detail="Invalid notification ID format")
    
    user_id = str(current_user["_id"])
    
    notification = await db.notifications.find_one({"_id": ObjectId(notification_id)})
    if not notification:
        raise HTTPException(status_code=404, detail="Notification not found")
    
    if notification.get("user_id") != user_id:
        raise HTTPException(status_code=403, detail="You can only mark your own notifications as read")
    
    result = await db.notifications.update_one(
        {"_id": ObjectId(notification_id)},
        {"$set": {"is_read": True}}
    )
    
    if result.modified_count == 0:
        raise HTTPException(status_code=404, detail="Notification not found or already marked as read")
    
    return {"message": "Notification marked as read"}

@app.put("/notifications/read-all")
async def mark_all_notifications_as_read(current_user: dict = Depends(get_current_user)):
    user_id = str(current_user["_id"])
    
    result = await db.notifications.update_many(
        {"user_id": user_id, "is_read": False},
        {"$set": {"is_read": True}}
    )
    
    return {"message": f"Marked {result.modified_count} notifications as read"}

@app.delete("/notifications/{notification_id}")
async def delete_notification(
    notification_id: str,
    current_user: dict = Depends(get_current_user)
):
    if not ObjectId.is_valid(notification_id):
        raise HTTPException(status_code=400, detail="Invalid notification ID format")
    
    user_id = str(current_user["_id"])
    
    notification = await db.notifications.find_one({"_id": ObjectId(notification_id)})
    if not notification:
        raise HTTPException(status_code=404, detail="Notification not found")
    
    if notification.get("user_id") != user_id:
        raise HTTPException(status_code=403, detail="You can only delete your own notifications")
    
    result = await db.notifications.delete_one({"_id": ObjectId(notification_id)})
    
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Notification not found")
    
    return {"message": "Notification deleted successfully"}

# Device Token Endpoint
@app.post("/users/me/device-token")
async def register_device_token(
    device_data: DeviceToken,
    current_user: dict = Depends(get_current_user)
):
    user_id = str(current_user["_id"])
    
    # Store the device token in the database
    await db.device_tokens.update_one(
        {"user_id": user_id, "device_token": device_data.device_token},
        {"$set": {
            "user_id": user_id,
            "device_token": device_data.device_token,
            "device_type": device_data.device_type,
            "updated_at": datetime.utcnow()
        }},
        upsert=True
    )
    
    return {"message": "Device token registered successfully"}

# Root endpoint
@app.get("/")
async def root():
    return {"message": "Welcome to LearnLive API"}

# Static files serving
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")

# Port finding and server startup
def find_available_port(start_port: int, max_port: int = 65535) -> Optional[int]:
    for port in range(start_port, max_port + 1):
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.bind(('0.0.0.0', port))
                return port
        except OSError:
            continue
    return None

if __name__ == "__main__":
    import uvicorn
    
    port = find_available_port(5000)
    if port is None:
        raise RuntimeError("No available ports found")
    
    print(f"Starting server on port {port}")
    uvicorn.run(app, host="192.168.29.230", port=port)

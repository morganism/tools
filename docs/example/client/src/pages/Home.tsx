import { useEffect, useRef, useState } from "react";
import "bootstrap/dist/css/bootstrap.min.css";
import "bootstrap/dist/js/bootstrap.bundle.min.js";
import flatpickr from "flatpickr";

/**
 * Design Philosophy: Neo-Skeuomorphic Minimalism
 * - Frosted glass navigation with blur backdrop
 * - Soft shadow system for depth
 * - Spring physics animations with bounce
 * - Apple-inspired blue spectrum palette
 */

export default function Home() {
  const [activeTab, setActiveTab] = useState("home");
  const [selectedOption, setSelectedOption] = useState("");
  const datePickerRef = useRef<HTMLInputElement>(null);
  const observerRef = useRef<IntersectionObserver | null>(null);

  // Initialize Flatpickr for date picker
  useEffect(() => {
    if (datePickerRef.current) {
      flatpickr(datePickerRef.current as any, {
        dateFormat: "Y-m-d",
      });
    }
  }, []);

  // Intersection Observer for scroll reveal animations
  useEffect(() => {
    observerRef.current = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("visible");
          }
        });
      },
      { threshold: 0.1 }
    );

    const elements = document.querySelectorAll(".reveal-on-scroll");
    elements.forEach((el) => observerRef.current?.observe(el));

    return () => {
      if (observerRef.current) {
        observerRef.current.disconnect();
      }
    };
  }, [activeTab]);

  // Register service worker
  useEffect(() => {
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker
        .register("/service-worker.js")
        .then((registration) => {
          console.log("Service Worker registered:", registration);
        })
        .catch((error) => {
          console.log("Service Worker registration failed:", error);
        });
    }
  }, []);

  const projects = [
    {
      title: "Project Alpha",
      description: "A revolutionary mobile application with AI integration",
      tags: ["React", "TypeScript", "AI", "Mobile"],
    },
    {
      title: "Project Beta",
      description: "E-commerce platform with real-time analytics",
      tags: ["Next.js", "Node.js", "PostgreSQL", "Analytics"],
    },
    {
      title: "Project Gamma",
      description: "Cloud-based collaboration tool for remote teams",
      tags: ["Vue.js", "Firebase", "WebRTC", "Cloud"],
    },
  ];

  const skills = [
    "JavaScript",
    "TypeScript",
    "React",
    "Node.js",
    "Python",
    "AWS",
    "Docker",
    "GraphQL",
    "MongoDB",
    "PostgreSQL",
    "Git",
    "CI/CD",
  ];

  return (
    <div className="min-h-screen" style={{ background: "var(--apple-light-gray)" }}>
      {/* Glassmorphic Navigation */}
      <nav
        className="glass fixed-top"
        style={{
          zIndex: 1000,
          borderRadius: "0",
        }}
      >
        <div className="container">
          <div className="d-flex justify-content-between align-items-center py-3">
            <div className="d-flex align-items-center">
              <div
                className="rounded-circle me-3"
                style={{
                  width: "40px",
                  height: "40px",
                  background: "linear-gradient(135deg, #007AFF, #5AC8FA)",
                  boxShadow: "inset 0 2px 4px rgba(0,0,0,0.1)",
                }}
              />
              <h4 className="mb-0 fw-bold" style={{ color: "var(--apple-dark)" }}>
                Portfolio
              </h4>
            </div>
            <div className="d-flex gap-3">
              <button
                className={`btn ${activeTab === "home" ? "btn-apple" : ""}`}
                onClick={() => setActiveTab("home")}
                style={
                  activeTab !== "home"
                    ? {
                        background: "transparent",
                        color: "var(--apple-gray)",
                        border: "none",
                        fontWeight: 600,
                      }
                    : {}
                }
              >
                Home
              </button>
              <button
                className={`btn ${activeTab === "projects" ? "btn-apple" : ""}`}
                onClick={() => setActiveTab("projects")}
                style={
                  activeTab !== "projects"
                    ? {
                        background: "transparent",
                        color: "var(--apple-gray)",
                        border: "none",
                        fontWeight: 600,
                      }
                    : {}
                }
              >
                Projects
              </button>
              <button
                className={`btn ${activeTab === "about" ? "btn-apple" : ""}`}
                onClick={() => setActiveTab("about")}
                style={
                  activeTab !== "about"
                    ? {
                        background: "transparent",
                        color: "var(--apple-gray)",
                        border: "none",
                        fontWeight: 600,
                      }
                    : {}
                }
              >
                About
              </button>
            </div>
          </div>
        </div>
      </nav>

      {/* Main Content */}
      <main style={{ paddingTop: "100px", paddingBottom: "60px" }}>
        <div className="container">
          {/* Home Tab */}
          {activeTab === "home" && (
            <div className="fade-in-up">
              {/* Hero Section */}
              <section className="text-center py-5 reveal-on-scroll">
                <h1
                  className="display-3 fw-bold mb-4"
                  style={{
                    color: "var(--apple-dark)",
                    letterSpacing: "-0.02em",
                  }}
                >
                  Welcome to My Portfolio
                </h1>
                <p
                  className="lead mb-4"
                  style={{
                    color: "var(--apple-gray)",
                    fontSize: "1.25rem",
                    maxWidth: "600px",
                    margin: "0 auto",
                  }}
                >
                  Crafting beautiful digital experiences with modern technologies
                </p>
                <div className="d-flex gap-3 justify-content-center">
                  <button
                    className="btn-apple"
                    data-bs-toggle="modal"
                    data-bs-target="#contactModal"
                  >
                    Get in Touch
                  </button>
                  <button
                    className="btn"
                    style={{
                      background: "white",
                      color: "var(--apple-blue)",
                      borderRadius: "12px",
                      padding: "12px 24px",
                      fontWeight: 600,
                      border: "2px solid var(--apple-blue)",
                    }}
                    onClick={() => setActiveTab("projects")}
                  >
                    View Projects
                  </button>
                </div>
              </section>

              {/* Alert Info */}
              <div className="alert alert-info reveal-on-scroll my-5" role="alert">
                <strong>🎉 New Feature!</strong> Check out the interactive date picker and
                custom combo box below.
              </div>

              {/* Interactive Components Section */}
              <section className="my-5 reveal-on-scroll">
                <div className="row g-4">
                  {/* Custom Combo Box */}
                  <div className="col-md-6">
                    <div className="card-apple">
                      <h5 className="fw-bold mb-3" style={{ color: "var(--apple-dark)" }}>
                        Select Your Interest
                      </h5>
                      <select
                        className="form-select"
                        value={selectedOption}
                        onChange={(e) => setSelectedOption(e.target.value)}
                      >
                        <option value="">Choose an option...</option>
                        <option value="web">Web Development</option>
                        <option value="mobile">Mobile Development</option>
                        <option value="design">UI/UX Design</option>
                        <option value="data">Data Science</option>
                      </select>
                      {selectedOption && (
                        <div className="mt-3 bounce-in">
                          <span className="badge" style={{
                            background: "var(--apple-blue)",
                            color: "white",
                            padding: "8px 16px",
                            borderRadius: "20px",
                            fontSize: "14px"
                          }}>
                            Selected: {selectedOption}
                          </span>
                        </div>
                      )}
                    </div>
                  </div>

                  {/* Date Picker */}
                  <div className="col-md-6">
                    <div className="card-apple">
                      <h5 className="fw-bold mb-3" style={{ color: "var(--apple-dark)" }}>
                        Schedule a Meeting
                      </h5>
                      <input
                        ref={datePickerRef}
                        type="text"
                        className="form-control"
                        placeholder="Select a date..."
                      />
                      <p className="mt-3 mb-0" style={{ color: "var(--apple-gray)", fontSize: "14px" }}>
                        Pick a date to schedule a consultation
                      </p>
                    </div>
                  </div>
                </div>
              </section>

              {/* Skills Tag Cloud */}
              <section className="my-5 reveal-on-scroll">
                <div className="card-apple">
                  <h4 className="fw-bold mb-4" style={{ color: "var(--apple-dark)" }}>
                    Technical Skills
                  </h4>
                  <div className="tag-cloud">
                    {skills.map((skill, index) => (
                      <span
                        key={skill}
                        className="tag"
                        style={{
                          animationDelay: `${index * 0.05}s`,
                        }}
                      >
                        {skill}
                      </span>
                    ))}
                  </div>
                </div>
              </section>
            </div>
          )}

          {/* Projects Tab */}
          {activeTab === "projects" && (
            <div className="fade-in-up">
              <h2 className="fw-bold mb-4" style={{ color: "var(--apple-dark)" }}>
                Featured Projects
              </h2>
              <div className="row g-4">
                {projects.map((project, index) => (
                  <div key={index} className="col-md-6 col-lg-4 reveal-on-scroll">
                    <div className="card-apple h-100">
                      <div
                        className="mb-3"
                        style={{
                          height: "200px",
                          background: `linear-gradient(135deg, ${
                            index % 2 === 0 ? "#007AFF, #5AC8FA" : "#5AC8FA, #007AFF"
                          })`,
                          borderRadius: "12px",
                        }}
                      />
                      <h5 className="fw-bold mb-2" style={{ color: "var(--apple-dark)" }}>
                        {project.title}
                      </h5>
                      <p style={{ color: "var(--apple-gray)", fontSize: "14px" }}>
                        {project.description}
                      </p>
                      <div className="tag-cloud mt-3">
                        {project.tags.map((tag) => (
                          <span key={tag} className="tag" style={{ fontSize: "12px" }}>
                            {tag}
                          </span>
                        ))}
                      </div>
                      <button
                        className="btn-apple mt-3 w-100"
                        data-bs-toggle="modal"
                        data-bs-target={`#projectModal${index}`}
                      >
                        View Details
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* About Tab */}
          {activeTab === "about" && (
            <div className="fade-in-up">
              <div className="row align-items-center">
                <div className="col-md-6 reveal-on-scroll">
                  <div
                    className="rounded-circle mx-auto mb-4"
                    style={{
                      width: "300px",
                      height: "300px",
                      background: "linear-gradient(135deg, #007AFF, #5AC8FA)",
                      boxShadow: "inset 0 4px 8px rgba(0,0,0,0.1), 0 8px 24px rgba(0,0,0,0.12)",
                    }}
                  />
                </div>
                <div className="col-md-6 reveal-on-scroll">
                  <h2 className="fw-bold mb-4" style={{ color: "var(--apple-dark)" }}>
                    About Me
                  </h2>
                  <p style={{ color: "var(--apple-gray)", fontSize: "18px", lineHeight: "1.6" }}>
                    I'm a passionate developer with expertise in building modern web applications.
                    With a focus on clean design and seamless user experiences, I bring ideas to
                    life through code.
                  </p>
                  <p style={{ color: "var(--apple-gray)", fontSize: "18px", lineHeight: "1.6" }}>
                    My approach combines technical excellence with aesthetic sensibility,
                    inspired by Apple's design philosophy of simplicity and elegance.
                  </p>
                  <button
                    className="btn-apple mt-3"
                    data-bs-toggle="modal"
                    data-bs-target="#contactModal"
                  >
                    Contact Me
                  </button>
                </div>
              </div>

              {/* Experience Timeline */}
              <section className="mt-5 reveal-on-scroll">
                <div className="card-apple">
                  <h4 className="fw-bold mb-4" style={{ color: "var(--apple-dark)" }}>
                    Experience
                  </h4>
                  <div className="position-relative">
                    {[
                      { year: "2023-Present", title: "Senior Developer", company: "Tech Corp" },
                      { year: "2021-2023", title: "Full Stack Developer", company: "StartupXYZ" },
                      { year: "2019-2021", title: "Frontend Developer", company: "Digital Agency" },
                    ].map((exp, index) => (
                      <div key={index} className="mb-4 pb-4" style={{
                        borderBottom: index < 2 ? "1px solid rgba(0,0,0,0.05)" : "none"
                      }}>
                        <div className="d-flex align-items-start">
                          <div
                            className="rounded-circle me-3"
                            style={{
                              width: "12px",
                              height: "12px",
                              background: "var(--apple-blue)",
                              marginTop: "6px",
                            }}
                          />
                          <div>
                            <p className="mb-1 fw-bold" style={{ color: "var(--apple-dark)" }}>
                              {exp.title}
                            </p>
                            <p className="mb-1" style={{ color: "var(--apple-gray)", fontSize: "14px" }}>
                              {exp.company}
                            </p>
                            <p className="mb-0" style={{ color: "var(--apple-light-blue)", fontSize: "12px" }}>
                              {exp.year}
                            </p>
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              </section>
            </div>
          )}
        </div>
      </main>

      {/* Contact Modal */}
      <div
        className="modal fade"
        id="contactModal"
        tabIndex={-1}
        aria-labelledby="contactModalLabel"
        aria-hidden="true"
      >
        <div className="modal-dialog modal-dialog-centered">
          <div className="modal-content">
            <div className="modal-header">
              <h5 className="modal-title fw-bold" id="contactModalLabel">
                Get in Touch
              </h5>
              <button
                type="button"
                className="btn-close"
                data-bs-dismiss="modal"
                aria-label="Close"
              ></button>
            </div>
            <div className="modal-body">
              <form>
                <div className="mb-3">
                  <label className="form-label fw-semibold">Name</label>
                  <input type="text" className="form-control" placeholder="Your name" />
                </div>
                <div className="mb-3">
                  <label className="form-label fw-semibold">Email</label>
                  <input type="email" className="form-control" placeholder="your@email.com" />
                </div>
                <div className="mb-3">
                  <label className="form-label fw-semibold">Message</label>
                  <textarea
                    className="form-control"
                    rows={4}
                    placeholder="Tell me about your project..."
                  ></textarea>
                </div>
              </form>
            </div>
            <div className="modal-footer">
              <button
                type="button"
                className="btn"
                data-bs-dismiss="modal"
                style={{
                  background: "var(--apple-light-gray)",
                  color: "var(--apple-dark)",
                  borderRadius: "12px",
                  fontWeight: 600,
                }}
              >
                Cancel
              </button>
              <button type="button" className="btn-apple">
                Send Message
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Project Detail Modals */}
      {projects.map((project, index) => (
        <div
          key={index}
          className="modal fade"
          id={`projectModal${index}`}
          tabIndex={-1}
          aria-hidden="true"
        >
          <div className="modal-dialog modal-dialog-centered modal-lg">
            <div className="modal-content">
              <div className="modal-header">
                <h5 className="modal-title fw-bold">{project.title}</h5>
                <button
                  type="button"
                  className="btn-close"
                  data-bs-dismiss="modal"
                  aria-label="Close"
                ></button>
              </div>
              <div className="modal-body">
                <div
                  className="mb-4"
                  style={{
                    height: "300px",
                    background: `linear-gradient(135deg, ${
                      index % 2 === 0 ? "#007AFF, #5AC8FA" : "#5AC8FA, #007AFF"
                    })`,
                    borderRadius: "12px",
                  }}
                />
                <p style={{ color: "var(--apple-gray)", fontSize: "16px", lineHeight: "1.6" }}>
                  {project.description}
                </p>
                <h6 className="fw-bold mt-4 mb-3">Technologies Used</h6>
                <div className="tag-cloud">
                  {project.tags.map((tag) => (
                    <span key={tag} className="tag">
                      {tag}
                    </span>
                  ))}
                </div>
                <h6 className="fw-bold mt-4 mb-3">Key Features</h6>
                <ul style={{ color: "var(--apple-gray)" }}>
                  <li>Responsive design for all devices</li>
                  <li>Modern UI with smooth animations</li>
                  <li>Optimized performance</li>
                  <li>Scalable architecture</li>
                </ul>
              </div>
              <div className="modal-footer">
                <button
                  type="button"
                  className="btn"
                  data-bs-dismiss="modal"
                  style={{
                    background: "var(--apple-light-gray)",
                    color: "var(--apple-dark)",
                    borderRadius: "12px",
                    fontWeight: 600,
                  }}
                >
                  Close
                </button>
                <button type="button" className="btn-apple">
                  Visit Project
                </button>
              </div>
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

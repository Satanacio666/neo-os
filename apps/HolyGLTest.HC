// HolyGLTest.HC - Native OpenGL 1.3/2.0 API test in HolyC
// NeoOS AArch64 Ring 0 SASOS

U0 TestGL() {
    "Testing HolyGL OpenGL 1.3/2.0 State Machine in HolyC...\n";
    glViewport(0, 0, 400, 300);
    glMatrixMode(0x1701); // GL_PROJECTION
    glLoadIdentity();
    gluPerspective(45.0, 1.333, 1.0, 100.0);
    glMatrixMode(0x1700); // GL_MODELVIEW
    glLoadIdentity();
    glTranslatef(0.0, 0.0, -5.0);
    glRotatef(25.0, 1.0, 0.0, 0.0);
    
    glBegin(0x0004); // GL_TRIANGLES
    glColor3f(1.0, 0.0, 0.0);
    glVertex3f(-1.0, -1.0, 0.0);
    glColor3f(0.0, 1.0, 0.0);
    glVertex3f(1.0, -1.0, 0.0);
    glColor3f(0.0, 0.0, 1.0);
    glVertex3f(0.0, 1.0, 0.0);
    glEnd();
    
    doldoc_print("$FG,GREEN$[HOLYGL] Successfully executed glBegin/glEnd OpenGL pipeline!$FG$\n");
}

TestGL();

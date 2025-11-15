pub const Offsets = struct {
    pub const InstanceClassDescriptor: u32 = 0x18;
    pub const InstanceName: u32 = 0xA8;
    pub const InstanceParent: u32 = 0x60;
    pub const InstanceChildren: u32 = 0x68;

    pub const ClassDescriptorName: u32 = 8;

    // REBoundFuncDescriptors = RemoteEvent->ClassDescriptor->BoundFuncDescriptors
    // UREBoundFuncDescriptors = UnreliableRemoteEvent->ClassDescriptor->BoundFuncDescriptors
    // RFBoundYieldDescriptors = RemoteFunction->ClassDescriptor->BoundYieldDescriptors

    pub const FireServerDescriptor: u32 = 0x75D9420; // REBoundFuncDescriptors 3 remoteevent rttis and select the last one
    pub const UnreliableFireServerDescriptor: u32 = 0x75E08F0; // UREBoundFuncDescriptors 3 unreliableremoteevent rttis and select the last one
    pub const InvokeServerDescriptor: u32 = 0x0; // RFBoundYieldDescriptors select the last one

    pub const BoundFuncDescriptorCallback: u32 = 0x88; // just find the pointer that points to a executeable memory, range 0x50 to 0x100
    pub const BoundYieldDescriptorCallback: u32 = 0x80; // ^ same as above
};
